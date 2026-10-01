import SwiftUI

@main
struct StayMountedApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(keeper: model.keeper, launchAtLogin: model.launchAtLogin)
        } label: {
            MenuBarLabel(keeper: model.keeper)
        }
        .menuBarExtraStyle(.window)
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
