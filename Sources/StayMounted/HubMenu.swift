import AppKit
import StayMountedKit

/// StayMounted's menu for ToolHUD's menu hub (see `MenuHub`). The menu bar item here is a
/// panel, which can't travel as a menu, so this offers each share's main actions and opens
/// the full panel in its window.
@MainActor
final class HubMenu: NSObject {
    private let keeper: MountKeeper
    private var symbol: () -> String

    init(keeper: MountKeeper, symbol: @escaping () -> String) {
        self.keeper = keeper
        self.symbol = symbol
    }

    func start() {
        MenuHub.shared.start(menu: { self.build() }, icon: {
            let image = NSImage(systemSymbolName: self.symbol(), accessibilityDescription: "StayMounted")
            image?.isTemplate = true
            return image
        })
    }

    private var settings: AppSettings { AppSettings.shared }

    private func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if settings.shares.isEmpty {
            menu.addItem(disabled: "No shares watched yet")
        }
        for share in settings.shares {
            let status = keeper.status(of: share)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.addItem(disabled: status.label)
            submenu.addItem(.separator())
            if case .mounted(let point) = status {
                submenu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder(_:)), target: self)
                    .representedObject = point
            } else {
                submenu.addItem(withTitle: "Mount Now", action: #selector(mountNow(_:)), target: self).representedObject = share.id
                submenu.addItem(withTitle: "Sign In…", action: #selector(signIn(_:)), target: self).representedObject = share.id
            }
            submenu.addItem(withTitle: "Open When Mounted…", action: #selector(openWhenMounted(_:)), target: self)
                .representedObject = share.id
            submenu.addItem(.separator())
            submenu.addItem(withTitle: share.paused ? "Resume Keeping Mounted" : "Pause",
                            action: #selector(togglePaused(_:)), target: self).representedObject = share.id
            let item = NSMenuItem(title: share.displayName, action: nil, keyEquivalent: "")
            item.state = status.isMounted ? .on : .off
            if status.needsAttention {
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause All Remounting", action: #selector(togglePausedAll), target: self)
            .state = settings.pausedAll ? .on : .off
        menu.addItem(withTitle: "Show Shares…", action: #selector(showShares), target: self)
        menu.addItem(.separator())

        #if !APPSTORE
        if let staged = AutoUpdater.shared.staged {
            menu.addItem(withTitle: "Update to \(staged.version) Now", action: #selector(installUpdate), target: self)
        } else if let pending = UpdateAvailability.shared.pending {
            menu.addItem(withTitle: "Update to \(pending)…", action: #selector(checkForUpdates), target: self)
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), target: self)
        }
        #endif
        menu.addItem(withTitle: "StayMounted Help", action: #selector(showHelp), target: self)
            .image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), target: self)
        menu.addItem(withTitle: "About StayMounted", action: #selector(showAbout), target: self)
        menu.addItem(withTitle: "Our other apps…", action: #selector(showOtherApps), target: self)
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StayMounted", action: #selector(quit), target: self)
        menu.addItem(.separator())
        menu.addItem(disabled: "\(AppInfo.name) \(AppInfo.displayVersion)")
        return menu
    }

    private func share(_ sender: NSMenuItem) -> WatchedShare? {
        settings.shares.first { $0.id == sender.representedObject as? WatchedShare.ID }
    }

    // MARK: - Actions

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let point = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: point))
    }

    @objc private func mountNow(_ sender: NSMenuItem) {
        if let share = share(sender) { keeper.mountNow(share, interactive: false) }
    }

    @objc private func signIn(_ sender: NSMenuItem) {
        if let share = share(sender) { keeper.mountNow(share, interactive: true) }
    }

    @objc private func openWhenMounted(_ sender: NSMenuItem) {
        if let share = share(sender) { LaunchItemsWindow.shared.show(share) }
    }

    @objc private func togglePaused(_ sender: NSMenuItem) {
        if let share = share(sender) { keeper.setPaused(share, !share.paused) }
    }

    @objc private func togglePausedAll() { keeper.setPausedAll(!settings.pausedAll) }
    @objc private func showShares() { SettingsWindow.shares.show() }
    @objc private func showHelp() { HelpWindow.shared.show() }
    @objc private func showSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    #if !APPSTORE
    @objc private func installUpdate() { AutoUpdater.shared.installNow() }
    @objc private func checkForUpdates() { UpdateController.checkForUpdates() }
    #endif

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }

    @objc private func openLog() {
        let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/StayMounted.log")
        NSWorkspace.shared.open(log)
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
        return item
    }

    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
