import AppKit
import SwiftUI

/// A SwiftUI view in an ordinary AppKit window. SwiftUI's own `Settings` scene can't be
/// opened from AppKit (the Dock menu, a relaunch), so both windows are hosted here.
@MainActor
final class SettingsWindow {
    /// StayMounted Settings: the preferences.
    static let shared = SettingsWindow(title: "StayMounted Settings")
    /// The menu bar panel in a window, for the Dock icon and for when the menu bar
    /// icon is hidden and this is the only way to reach the shares.
    static let shares = SettingsWindow(title: "StayMounted")

    /// Set once at launch by the app, which owns the objects the window shows.
    var makeContent: (() -> AnyView)?
    private let title: String
    private var window: NSWindow?

    private init(title: String) { self.title = title }

    func show() {
        if window == nil, let makeContent {
            let content = makeContent()
            // The view's natural size, with its height capped to the screen and the
            // content scrolling inside. Letting SwiftUI size the window to the content's
            // full height crashed once it grew taller than the screen: AppKit clamped the
            // window, SwiftUI asked to grow again, and AppKit aborted the
            // update-constraints loop.
            let natural = NSHostingView(rootView: content).fittingSize
            let hosting = NSHostingController(rootView: content.frame(maxHeight: .infinity))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .resizable]
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 80
            window.setContentSize(NSSize(width: natural.width, height: min(max(natural.height, 200), available)))
            window.contentMinSize = NSSize(width: natural.width, height: 200)
            window.contentMaxSize = NSSize(width: natural.width, height: CGFloat.greatestFiniteMagnitude)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The Dock icon's menu, and what happens when the app is opened again.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Runs a `staymounted://` URL; set by StayMountedApp.init, which owns the model.
    static var onURL: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let snapshot = ProcessInfo.processInfo.environment["STAYMOUNTED_DEBUG_HELP_TEST"] {
            DebugHelpTest.run(snapshot: snapshot, delegate: nil)
            return
        }
        #endif
        // A menu bar app; it has a Dock icon only if the user turned one on.
        if AppPresence.showInDock { AppPresence.applyDock() }
    }

    /// The Dock icon's right-click menu, when "Show in Dock" is on.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = AppPresence.dockMenu(title: "Settings…", target: self, action: #selector(showSettings))
        let shares = NSMenuItem(title: "Shares…", action: #selector(showShares), keyEquivalent: "")
        shares.target = self
        menu.insertItem(shares, at: 0)
        return menu
    }

    /// Clicking the Dock icon, or opening the app again from Applications or
    /// Spotlight. With the menu bar icon hidden that brings up the shares (whose
    /// window has Settings… too) — the way back when both icons are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppPresence.showInMenuBar { showSettings() } else { showShares() }
        return true
    }

    @objc func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc func showShares() {
        SettingsWindow.shares.show()
    }

    /// `staymounted://mount-all`, `pause` (pause or resume keeping everything mounted) and
    /// `shares` (from ToolHUD, Shortcuts or a script); anything else opens Settings.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "staymounted" {
            switch url.host {
            case "mount-all", "pause": Self.onURL?(url)
            case "shares": showShares()
            default: showSettings()
            }
        }
    }
}
