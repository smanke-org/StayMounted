import AppKit
import SwiftUI
import Observation

/// Owns the long-lived objects and starts them at launch.
///
/// Not hung off a view's `.task`: remounting has to run from the moment the app starts at
/// login, not from the first time someone opens the menu.
@Observable
@MainActor
final class AppModel {
    let keeper = MountKeeper()
    let launchAtLogin = LaunchAtLogin()
    let launcher: AppLauncher
    @ObservationIgnored private let gracePanel = EjectGracePanel()
    @ObservationIgnored private var previewWindow: NSWindow?

    init() {
        launcher = AppLauncher(keeper: keeper)
        // Before start(): shares already mounted at launch report as just mounted.
        keeper.onShareMounted = { [launcher] share in launcher.shareMounted(share) }
        LaunchItemsWindow.shared.launcher = launcher
        keeper.onHandEject = { [weak self] shares in self?.gracePanel.present(shares) }
        gracePanel.onRemount = { [weak self] ids in self?.keeper.remountAfterEject(ids) }
        gracePanel.onKeepEjected = { [weak self] ids in self?.keeper.keepEjected(ids) }

        Diagnostics.note("launch \(AppInfo.displayVersion) from \(Bundle.main.bundlePath)")
        keeper.start()
        launchAtLogin.enableOnFirstRun()
        scheduleLaunchUpdateCheck()
        openPreviewWindowIfRequested()
    }

    /// Deferred so startup is not waiting on the network, and silent unless there is
    /// something to offer.
    private func scheduleLaunchUpdateCheck() {
        #if !APPSTORE
        guard AppSettings.shared.checkForUpdatesAtLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            UpdateController.checkForUpdates(silent: true)
        }
        #endif
    }

    /// Development affordance: STAYMOUNTED_UI_PREVIEW=1 puts the menu's contents in an
    /// ordinary window, so the UI can be seen and driven without the menu bar.
    private func openPreviewWindowIfRequested() {
        guard ProcessInfo.processInfo.environment["STAYMOUNTED_UI_PREVIEW"] == "1" else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "StayMounted Preview"
        window.contentView = NSHostingView(rootView: MenuContentView(keeper: keeper, launchAtLogin: launchAtLogin))
        window.center()
        previewWindow = window
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }
}
