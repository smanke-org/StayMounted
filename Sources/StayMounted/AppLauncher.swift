import AppKit
import StayMountedKit

/// Opens a share's apps when it mounts.
///
/// Runs on every mount, not once per session: after a drop the apps may have been quit,
/// and anything still running is skipped. Never shows a dialog — a launch can happen at
/// login or after wake with nobody watching — so a missing app is logged and flagged in
/// the share's editor instead.
@MainActor
final class AppLauncher {
    private let settings = AppSettings.shared
    private let keeper: MountKeeper
    private var pending: [UUID: Task<Void, Never>] = [:]

    init(keeper: MountKeeper) {
        self.keeper = keeper
    }

    /// The share just mounted: wait its delay, then open what isn't running.
    func shareMounted(_ share: WatchedShare) {
        guard !share.apps.isEmpty else { return }
        schedule(share.id, delay: share.launchDelay)
    }

    /// "Open Now" in the editor: no delay, same rules otherwise.
    func openNow(_ shareID: UUID) {
        schedule(shareID, delay: 0)
    }

    private func schedule(_ id: UUID, delay: Int) {
        // A quick drop and remount replaces the earlier wait rather than adding a second.
        pending[id]?.cancel()
        pending[id] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.open(id)
        }
    }

    private func open(_ id: UUID) async {
        defer { pending[id] = nil }
        // Read the share again: the list may have been edited during the wait.
        guard let share = settings.shares.first(where: { $0.id == id }) else { return }
        guard keeper.isMountedNow(id) else {
            Diagnostics.note("\(share.displayName): unmounted before its apps were opened")
            return
        }
        for item in share.apps {
            guard !Task.isCancelled else { return }
            guard let url = Self.location(of: item) else {
                Diagnostics.note("\(share.displayName): can't find \(item.name) (\(item.bundleIdentifier ?? item.path))")
                continue
            }
            if Self.isRunning(item, at: url) {
                Diagnostics.note("\(share.displayName): \(item.name) already running")
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = !item.hidden
            configuration.hides = item.hidden
            configuration.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                Diagnostics.note("\(share.displayName): opened \(item.name)\(item.hidden ? " (hidden)" : "")")
            } catch {
                Diagnostics.note("\(share.displayName): couldn't open \(item.name): \(error.localizedDescription)")
            }
        }
    }

    /// Where the app is now: the path it was added from if it is still there, so a
    /// deliberately chosen copy wins; otherwise wherever LaunchServices has it.
    static func location(of item: LaunchItem) -> URL? {
        if FileManager.default.fileExists(atPath: item.path) {
            return URL(fileURLWithPath: item.path)
        }
        if let id = item.bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        return nil
    }

    private static func isRunning(_ item: LaunchItem, at url: URL) -> Bool {
        if let id = item.bundleIdentifier {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
        }
        let path = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == path }
    }
}
