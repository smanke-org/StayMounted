import AppKit
import SwiftUI

// MARK: - Content

/// One page of Help. `Help.resolve` swaps `{…}` tokens for the user's own settings, such
/// as their shortcuts, so the text matches what they've set up.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum HelpBlock {
    case text(String)
    case heading(String)
    /// Keys on the left, what they do on the right.
    case keys([(String, String)])
    case tip(String)

    var searchText: String {
        switch self {
        case .text(let s), .heading(let s), .tip(let s): Help.resolve(s)
        case .keys(let rows): rows.map { Help.resolve($0.0) + " " + Help.resolve($0.1) }.joined(separator: " ")
        }
    }
}

@MainActor
enum Help {
    /// StayMounted has no shortcuts the user sets, so nothing needs swapping.
    static func resolve(_ text: String) -> String { text }
    static var debugTokens: String { "" }
    static let testTabs = ["Settings"]
    static func topic(forSettingsTab tab: String) -> String { "getting-started" }

    static var topics: [HelpTopic] { [
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "sparkles", blocks: [
            .text("StayMounted keeps your network shares mounted. When Wi-Fi drops, the Mac sleeps, or a server restarts, it notices the share is gone and mounts it again as soon as the server answers."),
            .heading("Adding a share"),
            .text("Click the menu bar icon and type the share's address under \"Add a share\", such as smb://server/share, then Add. A share that's already mounted shows under \"Also mounted\"; click Keep Mounted to start watching it."),
            .text("StayMounted uses the password Finder saved in your keychain, so connect to the share once in Finder (Go › Connect to Server) and save the password. StayMounted stores no passwords of its own."),
            .heading("The menu bar icon"),
            .keys([
                ("Solid drive", "Everything watched is mounted"),
                ("Hollow drive", "Something is missing; StayMounted is waiting for the server"),
                ("Warning", "A share needs you, for example to sign in"),
                ("Drive with a minus", "Remounting is paused"),
            ]),
        ]),

        HelpTopic(id: "shares", title: "Managing Shares", symbol: "externaldrive.connected.to.line.below", blocks: [
            .text("Each share in the menu shows its status. Its menu offers:"),
            .keys([
                ("Mount Now / Mount", "Mount it right away"),
                ("Sign In…", "Mount it and enter a password if it needs one"),
                ("Show in Finder", "Open the mounted share"),
                ("Open When Mounted…", "Apps to open every time this share mounts"),
                ("Pause / Resume Keeping Mounted", "Stop or restart watching this share"),
                ("Stop Keeping Mounted", "Stop watching it (it stays mounted until you eject it)"),
            ]),
            .text("Pause All Remounting stops every share at once, for example while you work on the server."),
        ]),

        HelpTopic(id: "eject", title: "Ejecting a Share", symbol: "eject", blocks: [
            .text("When you eject a watched share yourself, StayMounted shows a small panel that counts down before mounting it again, so Eject doesn't look broken:"),
            .keys([
                ("Remount now", "Mount it again right away"),
                ("Keep ejected", "Leave it unmounted and pause it"),
            ]),
            .text("Turn off \"Ask before remounting a share I ejected\" in Settings to remount right away, as if the network had dropped it."),
        ]),

        HelpTopic(id: "open-when-mounted", title: "Opening Apps When Mounted", symbol: "app.badge.checkmark", blocks: [
            .text("Open When Mounted… lists apps to open, in order, whenever the share mounts, such as a photo library or a media server that needs the share. Apps that are already open are left alone."),
            .keys([
                ("Add App… or drag from Finder", "Add apps"),
                ("Wait before opening", "Give the share a moment first"),
                ("Hidden", "Open the app without bringing it forward"),
                ("Open Now", "Try the list right away"),
            ]),
        ]),

        HelpTopic(id: "settings", title: "Settings", symbol: "gearshape", blocks: [
            .text("Settings chooses login, the eject countdown, whether StayMounted shows in the Dock and the menu bar, the appearance, syncing settings with your other Macs, and updates. With the menu bar icon hidden, open StayMounted again from Finder or Spotlight to see your shares in a window."),
        ]),

        HelpTopic(id: "automation", title: "Automation", symbol: "gearshape.2", blocks: [
            .keys([
                ("staymounted://mount-all", "Mount every watched share that's missing (paused ones stay paused)"),
                ("staymounted://pause", "Pause or resume all remounting"),
            ]),
            .text("Use these links from Shortcuts, scripts or a launcher. ToolHUD's StayMounted buttons use them."),
        ]),

        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("A share keeps asking for a password"),
            .text("Connect once in Finder and choose to remember the password in your keychain, then use Mount Now."),
            .heading("\"Local Network access is off\""),
            .text("StayMounted can't check whether servers are answering, so it tries to mount without checking. Allow it in System Settings › Privacy & Security › Local Network."),
            .heading("Something went wrong"),
            .text("Open Log in the menu shows what StayMounted tried and what happened."),
        ]),
    ] }
}

// MARK: - Window

@Observable
@MainActor
final class HelpState {
    var selection: String? = "getting-started"
    var query = ""
}

@MainActor
final class HelpWindow: NSObject, NSWindowDelegate {
    static let shared = HelpWindow()

    let state = HelpState()
    private(set) var window: NSWindow?

    /// Opens Help, on `topic` when given.
    func show(topic: String? = nil) {
        if let topic { state.query = ""; state.selection = topic }
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(state: state))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "StayMounted Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let screen = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 820, height: min(600, screen - 80)))
            window.contentMinSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("StayMountedHelp")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @Bindable var state: HelpState

    private var matches: [HelpTopic] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Help.topics }
        return Help.topics.filter { topic in
            topic.title.lowercased().contains(query) || topic.blocks.contains { $0.searchText.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $state.selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .overlay {
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        } detail: {
            if let topic = Help.topics.first(where: { $0.id == state.selection }) {
                HelpPage(topic: topic, query: state.query)
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: state.query) {
            // Keep a matching topic on screen while searching.
            if let first = matches.first, !matches.contains(where: { $0.id == state.selection }) { state.selection = first.id }
        }
    }
}

struct HelpPage: View {
    let topic: HelpTopic
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .text(let s):
            Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(Help.resolve(s)).font(.title3.weight(.semibold)).padding(.top, 8)
        case .tip(let s):
            Label { Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .keys(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let keys = Help.resolve(row.0), what = Help.resolve(row.1)
                    let hit = !query.isEmpty && (keys + " " + what).lowercased().contains(query.lowercased())
                    GridRow {
                        Text(keys)
                            .font(.body.monospaced().weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            // The same key column width in every table on every page.
                            .frame(width: 210, alignment: .leading)
                        Text(what).fixedSize(horizontal: false, vertical: true)
                    }
                    .background(hit ? Color.yellow.opacity(0.25) : .clear)
                }
            }
        }
    }
}

/// The round "?" button macOS puts in the corner of settings panes.
struct HelpButton: NSViewRepresentable {
    let topic: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open))
        button.bezelStyle = .helpButton
        button.toolTip = "StayMounted Help"
        button.setAccessibilityLabel("Help")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.topic = topic }

    func makeCoordinator() -> Coordinator { Coordinator(topic: topic) }

    @MainActor
    final class Coordinator: NSObject {
        var topic: String
        init(topic: String) { self.topic = topic }
        @objc func open() { HelpWindow.shared.show(topic: topic) }
    }
}
