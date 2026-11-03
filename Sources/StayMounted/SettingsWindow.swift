import AppKit
import SwiftUI

/// A SwiftUI view in an ordinary AppKit window. SwiftUI's own `Settings` scene can't be
/// opened from AppKit (the Dock menu, a relaunch), so both windows are hosted here.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// StayMounted Settings: the preferences. It can be dragged wider as well as taller, and
    /// keeps the size it's dragged to.
    static let shared = SettingsWindow(title: "StayMounted Settings", formWidth: 460)
    /// The menu bar panel in a window, for the Dock icon and for when the menu bar
    /// icon is hidden and this is the only way to reach the shares.
    static let shares = SettingsWindow(title: "StayMounted", formWidth: nil)

    /// Set once at launch by the app, which owns the objects the window shows.
    var makeContent: (() -> AnyView)?
    private let title: String
    /// Settings' form width, the narrowest it can be dragged to; nil for the shares window,
    /// which keeps its content's own width.
    private let formWidth: CGFloat?
    private var window: NSWindow?

    private init(title: String, formWidth: CGFloat?) {
        self.title = title
        self.formWidth = formWidth
    }

    /// The lowest Settings can be dragged to.
    static let minimumHeight: CGFloat = 280

    /// The content size the user last dragged Settings to (per Mac, not synced), or nil
    /// while they haven't: then it opens at the form's own height.
    static var chosenSize: NSSize? {
        get { UserDefaults.standard.string(forKey: "settings.contentSize").map(NSSizeFromString) }
        set { UserDefaults.standard.set(newValue.map(NSStringFromSize), forKey: "settings.contentSize") }
    }

    func show() {
        if window == nil, let makeContent {
            let content = makeContent()
            // The view's natural size, with its height capped to the screen and the
            // content scrolling inside. Letting SwiftUI size the window to the content's
            // full height crashed once it grew taller than the screen: AppKit clamped the
            // window, SwiftUI asked to grow again, and AppKit aborted the
            // update-constraints loop.
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 80
            let window: NSWindow
            if let formWidth {
                // Measured at the form's width; it fills whatever size the user drags to.
                let natural = NSHostingView(rootView: content.frame(width: formWidth)).fittingSize.height
                let hosting = NSHostingController(rootView: content.frame(minWidth: formWidth, maxWidth: .infinity,
                                                                          maxHeight: .infinity))
                hosting.sizingOptions = []
                // Inside a plain container, so SwiftUI doesn't manage the window's size limits
                // (as the window's own content controller it cleared the minimum size whenever
                // a sheet came and went).
                let container = NSViewController()
                container.view = NSView(frame: NSRect(x: 0, y: 0, width: formWidth, height: 400))
                container.addChild(hosting)
                hosting.view.frame = container.view.bounds
                hosting.view.autoresizingMask = [.width, .height]
                container.view.addSubview(hosting.view)
                window = NSWindow(contentViewController: container)
                var size = NSSize(width: formWidth, height: min(max(natural, Self.minimumHeight), available))
                if let chosen = Self.chosenSize {
                    size = NSSize(width: max(chosen.width, formWidth),
                                  height: min(max(chosen.height, Self.minimumHeight), available))
                }
                window.setContentSize(size)
                window.contentMinSize = NSSize(width: formWidth, height: Self.minimumHeight)
                window.delegate = self
            } else {
                let natural = NSHostingView(rootView: content).fittingSize
                let hosting = NSHostingController(rootView: content.frame(maxHeight: .infinity))
                hosting.sizingOptions = []
                window = NSWindow(contentViewController: hosting)
                window.setContentSize(NSSize(width: natural.width, height: min(max(natural.height, 200), available)))
                window.contentMinSize = NSSize(width: natural.width, height: 200)
                window.contentMaxSize = NSSize(width: natural.width, height: CGFloat.greatestFiniteMagnitude)
            }
            window.title = title
            // Resizable as well as scrolling: drag it bigger to see more at once.
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        #if !APPSTORE
        // After an update whose notes weren't seen yet.
        if formWidth != nil, let window { WhatsNew.shared.present(on: window) }
        #endif
    }

    #if !APPSTORE
    /// This version's release notes, when asked for from Settings.
    func showWhatsNew() {
        if let window { WhatsNew.shared.present(on: window, asked: true) }
    }
    #endif

    /// A size the user dragged Settings to is kept, and used next time.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard formWidth != nil, let window else { return }
        Self.chosenSize = window.contentRect(forFrameRect: window.frame).size
    }

    #if DEBUG
    var debugWindow: NSWindow? { window }
    #endif
}

/// Quits StayMounted without asking: for quitting itself (installing an update, ending a test).
@MainActor
enum QuitConfirmation {
    private(set) static var confirmed = false

    static func quitNow() {
        confirmed = true
        NSApp.terminate(nil)
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
        if let how = ProcessInfo.processInfo.environment["STAYMOUNTED_DEBUG_QUIT_TEST"] {
            DebugQuitTest.run(how)
            return
        }
        #if !APPSTORE
        // The update prompt, What's New and Settings drawn to PNGs; starts nothing else.
        if let folder = ProcessInfo.processInfo.environment["STAYMOUNTED_DEBUG_UPDATE_NOTES"] {
            DebugUpdateNotes.run(folder: folder)
            return
        }
        #endif
        #endif
        #if DEBUG
        // A test copy of the agent CLI shows no Dock icon.
        if AgentSocket.isTestRun { return }
        #endif
        // A menu bar app; it has a Dock icon only if the user turned one on.
        if AppPresence.showInDock { AppPresence.applyDock() }
    }

    /// Quitting asks first, while "Ask before quitting" is on in Settings. Not when the Mac
    /// is logging out, restarting or shutting down (macOS gives the quit a reason then), and
    /// not when StayMounted quits itself to install an update.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        guard AppSettings.shared.confirmQuit, !QuitConfirmation.confirmed, !systemQuit else { return .terminateNow }

        // A menu bar app needs to be a regular one for the alert to come to the front; the
        // old policy goes back a runloop turn later, once the alert is gone (AppKit ignores
        // it while the modal still holds the app active).
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { DispatchQueue.main.async { NSApp.setActivationPolicy(previousPolicy) } }

        let alert = NSAlert()
        alert.messageText = "Quit StayMounted?"
        alert.informativeText = "Shares that drop aren't remounted until you open StayMounted again."
        // NSAlert puts a Cancel button on Esc, and Quit has no key, so Return does nothing:
        // quitting takes a click on Quit, never a stray keystroke.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit").keyEquivalent = ""
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.layout()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if alert.suppressionButton?.state == .on { AppSettings.shared.confirmQuit = false }
        return .terminateNow
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
