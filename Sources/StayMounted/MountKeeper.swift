import AppKit
import Network
import Observation
import StayMountedKit

/// What a watched share is doing, as the menu shows it.
enum ShareStatus: Equatable {
    case mounted(at: String)
    case checking
    case mounting
    case waitingForServer
    case needsSignIn
    case failed(String)
    /// Ejected by hand; remounting after the grace countdown unless told not to.
    case ejectPending
    case paused
    case pausedAll
    case notMounted

    var isMounted: Bool { if case .mounted = self { true } else { false } }

    var needsAttention: Bool {
        switch self {
        case .needsSignIn, .failed: true
        default: false
        }
    }
}

/// Keeps watched shares mounted.
///
/// Every trigger funnels into `sweep`, which looks at the mount table and tries each
/// watched share that is missing: at launch, on a timer, when the network changes, after
/// wake, and after an unmount. Each attempt first checks that the server is answering,
/// so being away from home costs a quick TCP probe rather than an error dialog.
///
/// Failures back off per share, and the backoff resets whenever the network changes —
/// the moment something new is most likely to work. A share whose password is missing or
/// rejected is never retried in the background: that only the user can fix.
@Observable
@MainActor
final class MountKeeper {
    private(set) var mounts: [MountedShare] = []
    private(set) var phases: [UUID: Phase] = [:]
    /// Shares counting down after a hand eject; see `EjectGracePanel`.
    private(set) var ejectPending: Set<UUID> = []
    /// Local Network access is denied, so servers can't be checked before mounting.
    /// Things still work; the menu suggests allowing it.
    private(set) var localNetworkBlocked = false
    /// Whether any probe has succeeded since launch. Until one has, a failed probe may
    /// only mean the Local Network permission is undecided.
    @ObservationIgnored private var probeHasWorked = false

    enum Phase: Equatable {
        case idle
        case checking
        case mounting
        case waitingForServer
        case needsSignIn
        case failed(MountFailure)
    }

    /// Asked to confirm a remount after a hand eject. Called with the shares concerned.
    @ObservationIgnored var onHandEject: (([WatchedShare]) -> Void)?
    /// A watched share has just appeared in the mount table, by any route: StayMounted,
    /// Finder, or already mounted when the app started (which is how login counts).
    @ObservationIgnored var onShareMounted: ((WatchedShare) -> Void)?

    @ObservationIgnored private let settings = AppSettings.shared
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var failures: [UUID: Int] = [:]
    @ObservationIgnored private var nextAttempt: [UUID: Date] = [:]
    @ObservationIgnored private var lastMountPoint: [UUID: String] = [:]
    /// Watched shares that were mounted at the last refresh. Starts empty, so shares
    /// already mounted at launch count as just mounted.
    @ObservationIgnored private var mountedIDs: Set<UUID> = []
    @ObservationIgnored private var lastDisruption: Date = .distantPast
    @ObservationIgnored private var networkUp = true
    @ObservationIgnored private var lastPathSignature: String?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// How often to look again even when nothing has happened. Cheap: a mount table read,
    /// plus a probe only for shares that are missing and due.
    private static let tick: TimeInterval = 15
    /// An unmount this soon after sleep, wake or a network change is the network's doing,
    /// not the user's, and is remounted without asking.
    private static let disruptionWindow: TimeInterval = 45

    // MARK: - Lifecycle

    func start() {
        refreshMounts()
        observeWorkspace()
        observeNetwork()
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep(reason: "timer") }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sweep(reason: "launch")
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        // Handlers get only the volume path, which is Sendable, so nothing non-Sendable
        // crosses into the main actor.
        func on(_ name: Notification.Name, _ handler: @escaping @MainActor (String?) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
                MainActor.assumeIsolated { handler(path) }
            })
        }

        on(NSWorkspace.didUnmountNotification) { [weak self] path in
            self?.volumeUnmounted(at: path)
        }
        on(NSWorkspace.didMountNotification) { [weak self] _ in
            self?.refreshMounts()
        }
        on(NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.lastDisruption = Date()
        }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in
            guard let self else { return }
            self.lastDisruption = Date()
            self.resetBackoff()
            // Wi-Fi typically takes a few seconds to rejoin after wake.
            self.sweep(reason: "wake", after: 3)
        }
        on(NSWorkspace.willPowerOffNotification) { [weak self] _ in
            // Logout and shutdown unmount everything; putting it back would only fight it.
            self?.shuttingDown = true
        }
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            // NWPathMonitor reports far more often than the network actually changes —
            // three times in 40 s on an idle Mac here — which made every hand eject look
            // like a network drop. Only the link state, the set of usable interfaces, and
            // which one is primary count as a change.
            let signature = "\(path.status)|" + path.availableInterfaces.map(\.name).joined(separator: ",")
            Task { @MainActor in self?.networkChanged(up: up, signature: signature) }
        }
        pathMonitor.start(queue: .main)
    }

    private func networkChanged(up: Bool, signature: String) {
        guard signature != lastPathSignature else { return }
        let first = lastPathSignature == nil
        lastPathSignature = signature
        let cameUp = up && !networkUp
        networkUp = up
        Diagnostics.note("network \(up ? "up" : "down") [\(signature)]")
        // The first report at launch is the starting state, not a change.
        guard !first else { return }
        lastDisruption = Date()
        guard up else { return }
        resetBackoff()
        // Give a fresh link a moment to get an address and DNS before probing.
        sweep(reason: cameUp ? "network up" : "network change", after: 2)
    }

    // MARK: - Status

    func status(of share: WatchedShare) -> ShareStatus {
        if let mount = mount(for: share) { return .mounted(at: mount.mountPoint) }
        if share.paused { return .paused }
        if settings.pausedAll { return .pausedAll }
        if ejectPending.contains(share.id) { return .ejectPending }
        switch phases[share.id] ?? .idle {
        case .idle: return .notMounted
        case .checking: return .checking
        case .mounting: return .mounting
        case .waitingForServer: return .waitingForServer
        case .needsSignIn: return .needsSignIn
        case .failed(let failure): return .failed(failure.message)
        }
    }

    func mount(for share: WatchedShare) -> MountedShare? {
        guard let key = share.share?.key else { return nil }
        return mounts.first { $0.key == key }
    }

    /// SMB shares mounted right now that are not being watched — offered with a
    /// "Keep mounted" button.
    var unwatchedMounts: [MountedShare] {
        let watched = Set(settings.shares.compactMap { $0.share?.key })
        var seen = Set<ShareKey>()
        return mounts.filter { !watched.contains($0.key) && seen.insert($0.key).inserted }
    }

    func refreshMounts() {
        mounts = MountTable.smbMounts()
        var nowMounted: Set<UUID> = []
        for share in settings.shares {
            if let mount = mount(for: share) {
                lastMountPoint[share.id] = mount.mountPoint
                nowMounted.insert(share.id)
            }
        }
        let appeared = nowMounted.subtracting(mountedIDs)
        mountedIDs = nowMounted
        for share in settings.shares where appeared.contains(share.id) {
            onShareMounted?(share)
        }
    }

    /// Reads the mount table afresh without touching `mounts`, so it can be asked from
    /// inside a mount callback without raising another one.
    func isMountedNow(_ id: UUID) -> Bool {
        guard let key = settings.shares.first(where: { $0.id == id })?.share?.key else { return false }
        return MountTable.smbMounts().contains { $0.key == key }
    }

    // MARK: - Editing

    enum AddResult: Equatable {
        case added
        case invalid
        case duplicate
    }

    @discardableResult
    func add(address: String) -> AddResult {
        guard let parsed = ShareURL(parsing: address) else { return .invalid }
        guard !settings.shares.contains(where: { $0.share?.key == parsed.key }) else { return .duplicate }
        let share = WatchedShare(address: parsed.url.absoluteString)
        settings.shares.append(share)
        Diagnostics.note("watching \(parsed.displayString)")
        refreshMounts()
        Task { await attempt(share, interactive: false) }
        return .added
    }

    func keepMounted(_ mount: MountedShare) {
        add(address: mount.source.url.absoluteString)
    }

    func remove(_ share: WatchedShare) {
        settings.shares.removeAll { $0.id == share.id }
        phases[share.id] = nil
        failures[share.id] = nil
        nextAttempt[share.id] = nil
        ejectPending.remove(share.id)
        mountedIDs.remove(share.id)
        LaunchItemsWindow.shared.close(share.id)
        Diagnostics.note("stopped watching \(share.displayName)")
    }

    func setPaused(_ share: WatchedShare, _ paused: Bool) {
        guard let index = settings.shares.firstIndex(where: { $0.id == share.id }) else { return }
        settings.shares[index].paused = paused
        ejectPending.remove(share.id)
        Diagnostics.note("\(share.displayName) \(paused ? "paused" : "resumed")")
        if !paused {
            clearBackoff(share.id)
            sweep(reason: "resumed")
        }
    }

    func setPausedAll(_ paused: Bool) {
        settings.pausedAll = paused
        Diagnostics.note(paused ? "paused all" : "resumed all")
        if !paused {
            resetBackoff()
            sweep(reason: "resumed all")
        }
    }

    // MARK: - Eject handling

    private func volumeUnmounted(at path: String?) {
        let before = Dictionary(uniqueKeysWithValues: lastMountPoint.map { ($0.value, $0.key) })
        refreshMounts()
        guard !shuttingDown, let path, let id = before[path],
              let share = settings.shares.first(where: { $0.id == id }),
              mount(for: share) == nil
        else { return }
        lastMountPoint[id] = nil

        let sinceDisruption = Date().timeIntervalSince(lastDisruption)
        let byNetwork = !networkUp || sinceDisruption < Self.disruptionWindow
        Diagnostics.note("\(share.displayName) unmounted from \(path) "
                         + "(\(byNetwork ? "network/sleep" : "likely by hand")"
                         + (lastDisruption == .distantPast ? ")" : ", \(Int(sinceDisruption))s since last network change or sleep)"))

        guard !share.paused, !settings.pausedAll else { return }
        if byNetwork || !settings.confirmAfterEject {
            clearBackoff(id)
            sweep(reason: "unmounted", after: 1)
        } else {
            ejectPending.insert(id)
            let pending = settings.shares.filter { ejectPending.contains($0.id) }
            onHandEject?(pending)
        }
    }

    /// The grace countdown ran out, or "Remount now" was pressed.
    func remountAfterEject(_ ids: Set<UUID>) {
        ejectPending.subtract(ids)
        for id in ids { clearBackoff(id) }
        sweep(reason: "eject grace over")
    }

    /// "Keep ejected": pause these shares until resumed from the menu.
    func keepEjected(_ ids: Set<UUID>) {
        for share in settings.shares where ids.contains(share.id) {
            setPaused(share, true)
        }
        ejectPending.subtract(ids)
    }

    // MARK: - Mounting

    /// Tries every watched share that is missing and due.
    func sweep(reason: String, after delay: TimeInterval = 0) {
        if delay > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.sweep(reason: reason)
            }
            return
        }
        refreshMounts()
        guard !settings.pausedAll, !shuttingDown else { return }

        let now = Date()
        for share in settings.shares {
            guard !share.paused, !ejectPending.contains(share.id), !inFlight.contains(share.id),
                  mount(for: share) == nil
            else { continue }
            if phases[share.id] == .needsSignIn { continue }
            if let due = nextAttempt[share.id], due > now { continue }
            if reason != "timer" { Diagnostics.note("sweep (\(reason)): trying \(share.displayName)") }
            Task { await attempt(share, interactive: false) }
        }
    }

    /// "Mount now" and "Sign in…" from the menu: tries at once, ignoring backoff.
    /// Interactive lets NetAuth show its password sheet.
    func mountNow(_ share: WatchedShare, interactive: Bool) {
        clearBackoff(share.id)
        ejectPending.remove(share.id)
        Task { await attempt(share, interactive: interactive) }
    }

    private func attempt(_ share: WatchedShare, interactive: Bool) async {
        guard let target = share.share, !inFlight.contains(share.id) else { return }
        inFlight.insert(share.id)
        defer { inFlight.remove(share.id) }

        // Probing first keeps an absent server quiet and quick. A sign-in attempt skips it:
        // the user is asking, and NetFS will say if the server is missing.
        var probeFailed = false
        if !interactive {
            phases[share.id] = .checking
            switch await Reachability.check(host: target.host) {
            case .reachable:
                probeHasWorked = true
                localNetworkBlocked = false
            case .unreachable(let reason):
                if failures[share.id] == nil { Diagnostics.note("\(share.displayName): probe of \(target.host) failed: \(reason)") }
                // While the Local Network prompt is unanswered, the probe just times out
                // rather than reporting a denial. Until a probe has worked at least once,
                // a failed one proves nothing, so try the (silent) mount anyway.
                guard !probeHasWorked else {
                    phases[share.id] = .waitingForServer
                    backOff(share, failure: .unreachable)
                    return
                }
                probeFailed = true
            case .blockedByPrivacy:
                // Can't look, so just try: a no-UI mount of an absent server fails quietly.
                if !localNetworkBlocked { Diagnostics.note("local network access not allowed; mounting without a probe") }
                localNetworkBlocked = true
            }
        }

        phases[share.id] = .mounting
        let restorePolicy = interactive ? beginInteraction() : nil
        let result = await Mounter.mount(target, interactive: interactive)
        restorePolicy?()
        refreshMounts()

        switch result {
        case .success(let points):
            if probeFailed {
                // The server was there all along: the probe is what's blocked.
                Diagnostics.note("mounted although the probe failed; local network access is likely not allowed")
                localNetworkBlocked = true
            }
            phases[share.id] = .idle
            clearBackoff(share.id)
            Diagnostics.note("mounted \(target.displayString) at \(points.first ?? "?")")
        case .failure(let failure):
            switch failure {
            case .needsSignIn, .cancelled:
                phases[share.id] = .needsSignIn
            case .unreachable:
                phases[share.id] = .waitingForServer
            default:
                phases[share.id] = .failed(failure)
            }
            backOff(share, failure: failure)
        }
    }

    private func backOff(_ share: WatchedShare, failure: MountFailure) {
        let count = (failures[share.id] ?? 0) + 1
        failures[share.id] = count
        // An absent server is cheap to re-probe and comes back on its own (a NAS rebooting
        // does not change the network), so it is checked often. Real mount errors wait longer.
        let base: Double = failure == .unreachable ? 15 : 30
        let cap: Double = failure == .unreachable ? 120 : 600
        let delay = min(base * pow(2, Double(count - 1)), cap)
        nextAttempt[share.id] = Date().addingTimeInterval(delay)
        Diagnostics.note("\(share.displayName): \(failure.message); next try in \(Int(delay))s")
    }

    private func clearBackoff(_ id: UUID) {
        failures[id] = nil
        nextAttempt[id] = nil
        if phases[id] != .needsSignIn { phases[id] = .idle }
    }

    /// After a network change, every waiting share is worth trying again now.
    /// A share waiting on a password stays waiting; that needs the user.
    private func resetBackoff() {
        failures.removeAll()
        nextAttempt.removeAll()
        for (id, phase) in phases where phase != .needsSignIn { phases[id] = .idle }
    }

    /// NetAuth draws its sign-in sheet in its own process, but a menu bar app that is not
    /// active can leave it behind other windows. Becoming a regular app for the duration
    /// brings it forward. The accessory policy is restored on the next runloop turn:
    /// AppKit ignores the change while the app is still active from the dialog.
    private func beginInteraction() -> () -> Void {
        let previous = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        return {
            DispatchQueue.main.async { NSApp.setActivationPolicy(previous) }
        }
    }
}
