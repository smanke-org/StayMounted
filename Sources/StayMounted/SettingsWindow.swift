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
            let hosting = NSHostingController(rootView: makeContent())
            // The window takes the view's own size; without this a grouped Form has
            // no natural height and the window opens as a sliver.
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable]
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
    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
