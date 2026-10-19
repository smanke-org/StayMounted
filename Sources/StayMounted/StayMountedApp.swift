import SwiftUI

@main
struct StayMountedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var settings = AppSettings.shared

    init() {
        #if !APPSTORE
        AppModel.newInstall = SettingsSync.domainIsEmpty()
        #endif
        let model = AppModel()
        _model = State(initialValue: model)
        SettingsWindow.shared.makeContent = {
            AnyView(SettingsView(launchAtLogin: model.launchAtLogin))
        }
        SettingsWindow.shares.makeContent = {
            // Scrolls once there are more shares than fit on the screen.
            AnyView(ScrollView { MenuContentView(keeper: model.keeper) })
        }
        AppDelegate.onURL = { url in
            let keeper = model.keeper
            switch url.host {
            case "mount-all":
                // Every watched share that's simply missing; paused ones stay paused.
                for share in AppSettings.shared.shares {
                    switch keeper.status(of: share) {
                    case .notMounted, .waitingForServer, .failed: keeper.mountNow(share, interactive: false)
                    default: break
                    }
                }
            case "pause":
                keeper.setPausedAll(!AppSettings.shared.pausedAll)
            default:
                break
            }
        }
    }

    var body: some Scene {
        // The panel can remove the menu bar icon; the app then lives in the Dock, or nowhere.
        MenuBarExtra(isInserted: $settings.showInMenuBar) {
            MenuContentView(keeper: model.keeper)
        } label: {
            MenuBarLabel(keeper: model.keeper)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // The app menu, while there is a Dock icon.
            CommandGroup(after: .appInfo) {
                // Right below About: the developer's site, which lists every app.
                Button("Our other apps…") { if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) } }
            }
            CommandGroup(replacing: .help) {
                Button("StayMounted Help") { HelpWindow.shared.show() }
                    .keyboardShortcut("?", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// The menu bar item doubles as the status light: a solid drive when everything watched
/// is mounted, hollow while something is missing, a warning when one needs the user.
struct MenuBarLabel: View {
    let keeper: MountKeeper
    @State private var settings = AppSettings.shared

    private var statuses: [ShareStatus] {
        settings.shares.map { keeper.status(of: $0) }
    }

    private var symbol: String {
        if settings.pausedAll { return "externaldrive.badge.minus" }
        let active = statuses.filter { $0 != .paused }
        if active.contains(where: \.needsAttention) { return "externaldrive.badge.exclamationmark" }
        if !active.isEmpty, active.allSatisfy(\.isMounted) { return "externaldrive.connected.to.line.below.fill" }
        return "externaldrive.connected.to.line.below"
    }

    private var accessibilityDescription: String {
        let mounted = statuses.filter(\.isMounted).count
        if settings.pausedAll { return "StayMounted: paused" }
        return "StayMounted: \(mounted) of \(statuses.count) shares mounted"
    }

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(accessibilityDescription)
    }
}
