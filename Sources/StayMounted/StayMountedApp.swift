import SwiftUI

@main
struct StayMountedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var settings = AppSettings.shared

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        SettingsWindow.shared.makeContent = {
            AnyView(MenuContentView(keeper: model.keeper, launchAtLogin: model.launchAtLogin))
        }
    }

    var body: some Scene {
        // The panel can remove the menu bar icon; the app then lives in the Dock, or nowhere.
        MenuBarExtra(isInserted: $settings.showInMenuBar) {
            MenuContentView(keeper: model.keeper, launchAtLogin: model.launchAtLogin)
        } label: {
            MenuBarLabel(keeper: model.keeper)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // The app menu, while there is a Dock icon: Settings… opens the panel in a window.
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
