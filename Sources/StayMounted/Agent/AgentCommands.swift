import AppKit
import Foundation
import StayMountedKit

// StayMounted's commands for `staymounted` and its MCP server. Each one runs in the app, on
// the main actor, through the same MountKeeper and AppSettings calls as the menu bar panel,
// so the panel shows the change at once.
//
// Passwords never pass through here: StayMounted mounts with the ones Finder saved in the
// keychain (NetAuth reads them, the app never does), results never show the user name in an
// address, and `shares add` refuses an address that carries a password.

enum AgentCommands {
    @MainActor private static var model: AppModel {
        get throws {
            guard let model = AppModel.current else { throw AgentError.unavailable("StayMounted is still starting. Try again") }
            return model
        }
    }

    @MainActor private static var keeper: MountKeeper { get throws { try model.keeper } }
    @MainActor private static var settings: AppSettings { AppSettings.shared }

    private static let yesHint = "nothing changed yet. Add --yes to do it (over MCP: set yes to true)"

    static let all: [AgentCommand] = [
        AgentCommand(
            name: "status",
            summary: "Version, whether keeping shares mounted is paused, and how many watched shares are mounted or need attention.",
            example: "staymounted status --json",
            readOnly: true,
            run: { _ in
                let keeper = try keeper
                keeper.refreshMounts()
                let statuses = settings.shares.map { keeper.status(of: $0) }
                return [
                    "version": AppInfo.version,
                    "paused": settings.pausedAll,
                    "shares": statuses.count,
                    "mounted": statuses.filter(\.isMounted).count,
                    "needAttention": statuses.filter(\.needsAttention).count,
                    "otherSMBMounts": keeper.unwatchedMounts.count,
                    "localNetworkBlocked": keeper.localNetworkBlocked,
                    "testCopy": AgentSocket.isTestRun,
                ] as JSONObject
            }),

        AgentCommand(
            name: "shares list",
            summary: "The watched shares: server, share, whether each is mounted (and where), its state and its last error.",
            params: [
                .init(name: "state", help: "only shares in this state: mounted, not-mounted (anything not mounted), attention (sign in needed or failed), paused"),
                .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                .init(name: "offset", kind: .integer, help: "skip this many, for the next page"),
            ],
            example: "staymounted shares list --state not-mounted --json",
            readOnly: true,
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                var shares = settings.shares
                if let state = args.string("state") {
                    let keep: (ShareStatus) -> Bool
                    switch state.lowercased() {
                    case "mounted": keep = { $0.isMounted }
                    case "not-mounted", "notmounted", "missing": keep = { !$0.isMounted }
                    case "attention": keep = { $0.needsAttention }
                    case "paused": keep = { $0 == .paused || $0 == .pausedAll }
                    default: throw AgentError.usage("--state must be mounted, not-mounted, attention or paused, not \"\(state)\"")
                    }
                    shares = shares.filter { keep(keeper.status(of: $0)) }
                }
                return try page(shares.map { summary($0, keeper: keeper) }, key: "shares", args: args)
            }),

        AgentCommand(
            name: "shares show",
            summary: "One watched share in full: its state and last error, where it's mounted, and the apps it opens when it mounts.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares show Media --json",
            readOnly: true,
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                let share = try find(try args.required("share"))
                var result = summary(share, keeper: keeper)
                result["openWhenMounted"] = share.apps.map { app -> JSONObject in
                    ["name": app.name, "hidden": app.hidden, "bundleID": null(app.bundleIdentifier)]
                }
                result["openDelaySeconds"] = share.launchDelay
                return result
            }),

        AgentCommand(
            name: "mounts list",
            summary: "Every SMB share mounted on this Mac right now, watched or not (unwatched ones can be added with shares add).",
            example: "staymounted mounts list --json",
            readOnly: true,
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                var seen = Set<String>()
                let mounts = keeper.mounts.filter { seen.insert($0.mountPoint).inserted }.map { mount -> JSONObject in
                    let watched = settings.shares.first { $0.share?.key == mount.key }
                    return ["mountPoint": mount.mountPoint, "server": mount.source.displayHost, "share": mount.source.share,
                            "address": mount.source.displayString, "watched": watched != nil,
                            "id": null(watched.map { shortID($0.id) })]
                }
                return try page(mounts, key: "mounts", args: args)
            }),

        AgentCommand(
            name: "shares add",
            summary: "Start keeping a share mounted, as the panel's Add button does; StayMounted mounts it at once with the password Finder saved in the keychain.",
            params: [.init(name: "address", required: true, help: "smb://server/share (also \\\\server\\share or server/share), never with a password")],
            example: "staymounted shares add --address smb://nas.local/Media --json",
            run: { args in
                let keeper = try keeper
                let address = try args.required("address")
                if carriesPassword(address) {
                    throw AgentError.invalid("leave the password out of the address. StayMounted never takes passwords: connect "
                                             + "once in Finder (Go > Connect to Server) and save the password in the keychain")
                }
                switch keeper.add(address: address) {
                case .invalid:
                    throw AgentError.usage("\"\(address)\" isn't an SMB share address. Example: staymounted shares add --address smb://nas.local/Media")
                case .duplicate:
                    let key = ShareURL(parsing: address)?.key
                    let existing = settings.shares.first { $0.share?.key == key }
                    var result: JSONObject = ["added": false, "note": "already watched"]
                    if let existing { result["share"] = summary(existing, keeper: keeper) }
                    return result
                case .added:
                    guard let share = settings.shares.last else { return ["added": true] as JSONObject }
                    return ["added": true, "share": summary(share, keeper: keeper),
                            "next": "it's being mounted now; check with `staymounted shares show \(shortID(share.id))`"] as JSONObject
                }
            }),

        AgentCommand(
            name: "shares remove",
            summary: "Stop keeping a share mounted, as Stop Keeping Mounted does. It stays mounted for now; its Open When Mounted apps are forgotten.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares remove 3f2a9c1e --yes --json",
            destructive: true,
            run: { args in
                let keeper = try keeper
                let share = try find(try args.required("share"))
                let shown = summary(share, keeper: keeper)
                guard args.confirmed else {
                    return ["removed": false, "wouldRemove": shown, "appsForgotten": share.apps.count, "hint": yesHint] as JSONObject
                }
                keeper.remove(share)
                return ["removed": true, "share": shown] as JSONObject
            }),

        AgentCommand(
            name: "shares mount",
            summary: "Mount a watched share now, as Mount Now does (no waiting for the next try), or with --all every watched share that's missing, as staymounted://mount-all does.",
            params: [
                .init(name: "share", positional: true, help: "the share's id (or any unique start of it) or its share name"),
                .init(name: "all", kind: .boolean, help: "every watched share that's missing; paused ones stay paused"),
                .init(name: "sign-in", kind: .boolean, help: "let macOS show its sign-in window if the keychain has no password (only when the person asked; they type it, never you)"),
            ],
            example: "staymounted shares mount Media --json",
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                if try args.bool("all") == true {
                    guard args.string("share") == nil else { throw AgentError.usage("give a share or --all, not both") }
                    let tried = keeper.mountAllMissing()
                    return ["mounting": tried.map { summary($0, keeper: keeper) },
                            "next": "check with `staymounted shares list`"] as JSONObject
                }
                guard let name = args.string("share") else {
                    throw AgentError.usage("missing <share> or --all. Example: staymounted shares mount Media")
                }
                let share = try find(name)
                if let mount = keeper.mount(for: share) {
                    return ["changed": false, "note": "already mounted", "mountPoint": mount.mountPoint] as JSONObject
                }
                keeper.mountNow(share, interactive: try args.bool("sign-in") == true)
                return ["mounting": true, "share": summary(share, keeper: keeper),
                        "next": "check with `staymounted shares show \(shortID(share.id))`"] as JSONObject
            }),

        AgentCommand(
            name: "shares unmount",
            summary: "Unmount a watched share now, the way Finder ejects it, and pause it so it isn't mounted again until shares resume. Apps with files open on it lose them.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares unmount Media --yes --json",
            destructive: true,
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                let share = try find(try args.required("share"))
                guard let mount = keeper.mount(for: share) else {
                    return ["changed": false, "note": "not mounted"] as JSONObject
                }
                guard args.confirmed else {
                    return ["unmounted": false, "wouldUnmount": mount.mountPoint, "wouldPause": !share.paused,
                            "share": summary(share, keeper: keeper), "hint": yesHint] as JSONObject
                }
                let point = keeper.unmount(share, thenRemount: false)
                return ["unmounting": null(point), "paused": true,
                        "next": "check with `staymounted shares show \(shortID(share.id))`; `staymounted shares resume` mounts it again"] as JSONObject
            }),

        AgentCommand(
            name: "shares remount",
            summary: "Unmount a watched share and mount it again at once, for a share that's mounted but stuck. Apps with files open on it lose them.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares remount Media --yes --json",
            destructive: true,
            run: { args in
                let keeper = try keeper
                keeper.refreshMounts()
                let share = try find(try args.required("share"))
                if share.paused || settings.pausedAll {
                    throw AgentError.invalid("\(share.displayName) is paused, so it wouldn't be mounted again. "
                                             + "Run `staymounted \(share.paused ? "shares resume \(shortID(share.id))" : "resume")` first")
                }
                guard let mount = keeper.mount(for: share) else {
                    throw AgentError.invalid("\(share.displayName) isn't mounted. Run `staymounted shares mount \(shortID(share.id))`")
                }
                guard args.confirmed else {
                    return ["remounted": false, "wouldRemount": mount.mountPoint, "share": summary(share, keeper: keeper),
                            "hint": yesHint] as JSONObject
                }
                let point = keeper.unmount(share, thenRemount: true)
                return ["remounting": null(point),
                        "next": "check with `staymounted shares show \(shortID(share.id))`"] as JSONObject
            }),

        AgentCommand(
            name: "shares pause",
            summary: "Stop keeping one share mounted for now, as its Pause menu item does. It isn't unmounted.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares pause Media --json",
            run: { args in
                let keeper = try keeper
                let share = try find(try args.required("share"))
                guard !share.paused else { return ["changed": false, "share": summary(share, keeper: keeper)] as JSONObject }
                keeper.setPaused(share, true)
                return ["changed": true, "share": summary(try find(shortID(share.id)), keeper: keeper)] as JSONObject
            }),

        AgentCommand(
            name: "shares resume",
            summary: "Keep one paused share mounted again, as Resume does; it's mounted at once if it's missing.",
            params: [.init(name: "share", required: true, positional: true, help: "the share's id (or any unique start of it) or its share name")],
            example: "staymounted shares resume Media --json",
            run: { args in
                let keeper = try keeper
                let share = try find(try args.required("share"))
                guard share.paused else { return ["changed": false, "share": summary(share, keeper: keeper)] as JSONObject }
                keeper.setPaused(share, false)
                return ["changed": true, "share": summary(try find(shortID(share.id)), keeper: keeper)] as JSONObject
            }),

        AgentCommand(
            name: "pause",
            summary: "Pause keeping every share mounted, as the panel's switch and staymounted://pause do. Nothing is unmounted or forgotten.",
            example: "staymounted pause --json",
            run: { _ in
                let keeper = try keeper
                guard !settings.pausedAll else { return ["changed": false, "paused": true] as JSONObject }
                keeper.setPausedAll(true)
                return ["changed": true, "paused": true] as JSONObject
            }),

        AgentCommand(
            name: "resume",
            summary: "Resume keeping every share mounted; missing ones are mounted at once.",
            example: "staymounted resume --json",
            run: { _ in
                let keeper = try keeper
                guard settings.pausedAll else { return ["changed": false, "paused": false] as JSONObject }
                keeper.setPausedAll(false)
                return ["changed": true, "paused": false] as JSONObject
            }),

        AgentCommand(
            name: "open",
            summary: "Show a StayMounted window: shares (the panel in a window), settings, or help.",
            params: [.init(name: "page", required: true, positional: true, help: "shares, settings or help")],
            example: "staymounted open shares",
            run: { args in
                let page = try args.required("page").lowercased()
                switch page {
                case "shares": SettingsWindow.shares.show()
                case "settings":
                    if AgentSocket.isTestRun {
                        throw AgentError.invalid("a test copy doesn't show Settings: they are the installed app's")
                    }
                    SettingsWindow.shared.show()
                case "help": HelpWindow.shared.show()
                default: throw AgentError.usage("there's no page \"\(page)\". Pages: shares, settings, help")
                }
                return ["opened": page] as JSONObject
            }),
    ]

    // MARK: Helpers

    /// A missing value as JSON null.
    private static func null(_ value: String?) -> Any { value ?? NSNull() }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    /// A share by any unique start of its id, or by its share name (or address) when only one matches.
    @MainActor private static func find(_ text: String) throws -> WatchedShare {
        let needle = text.lowercased().replacingOccurrences(of: "-", with: "")
        let shares = settings.shares
        let byID = shares.filter { $0.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(needle) }
        if byID.count == 1 { return byID[0] }
        let key = ShareURL(parsing: text)?.key
        let byName = shares.filter { share in
            share.displayName.lowercased() == text.lowercased() || (key != nil && share.share?.key == key)
        }
        if byName.count == 1 { return byName[0] }
        if byID.count > 1 || byName.count > 1 {
            throw AgentError.invalid("\"\(text)\" matches more than one share. Use the id from `staymounted shares list`")
        }
        throw AgentError.notFound("no watched share \"\(text)\". Run `staymounted shares list`")
    }

    /// What an agent needs about one share. The address never shows a user name.
    @MainActor private static func summary(_ share: WatchedShare, keeper: MountKeeper) -> JSONObject {
        let status = keeper.status(of: share)
        var result: JSONObject = [
            "id": shortID(share.id),
            "name": share.displayName,
            "server": null(share.share?.displayHost),
            "share": null(share.share?.share),
            "address": null(share.share?.displayString),
            "mounted": status.isMounted,
            "state": code(status),
            "stateLabel": status.label,
            "paused": share.paused,
            "lastError": null(lastError(share, keeper: keeper)),
        ]
        if case .mounted(let point) = status { result["mountPoint"] = point }
        return result
    }

    private static func code(_ status: ShareStatus) -> String {
        switch status {
        case .mounted: "mounted"
        case .checking: "checking"
        case .mounting: "mounting"
        case .waitingForServer: "waiting_for_server"
        case .needsSignIn: "needs_sign_in"
        case .failed: "failed"
        case .ejectPending: "eject_pending"
        case .paused: "paused"
        case .pausedAll: "paused_all"
        case .notMounted: "not_mounted"
        }
    }

    /// The last mount or unmount failure, as the panel words it.
    @MainActor private static func lastError(_ share: WatchedShare, keeper: MountKeeper) -> String? {
        if let message = keeper.unmountErrors[share.id] { return "Unmount failed: \(message)" }
        switch keeper.phases[share.id] {
        case .failed(let failure): return failure.message
        case .needsSignIn: return MountFailure.needsSignIn.message
        case .waitingForServer: return MountFailure.unreachable.message
        default: return nil
        }
    }

    /// `user:password@` in an address. ShareURL drops the password, but it shouldn't be sent at all.
    private static func carriesPassword(_ address: String) -> Bool {
        var text = address.replacingOccurrences(of: "\\", with: "/")
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        while text.hasPrefix("/") { text.removeFirst() }
        let authority = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        guard let at = authority.lastIndex(of: "@") else { return false }
        return authority[..<at].contains(":")
    }

    private static func page(_ items: [JSONObject], key: String, args: Args) throws -> JSONObject {
        let limit = max(1, try args.int("limit", default: 50))
        let offset = max(0, try args.int("offset", default: 0))
        let slice = Array(items.dropFirst(offset).prefix(limit))
        var result: JSONObject = [key: slice, "total": items.count]
        if offset + slice.count < items.count { result["nextOffset"] = offset + slice.count }
        return result
    }
}
