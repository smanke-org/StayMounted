import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StayMountedKit

/// "Open When Mounted…": a share's app list, in an ordinary window.
///
/// Not in the menu bar panel: an open panel started from there dismisses the panel, and
/// list reordering needs a drag session the panel never delivers.
@MainActor
final class LaunchItemsWindow {
    static let shared = LaunchItemsWindow()

    /// Set once at launch, for "Open Now".
    var launcher: AppLauncher?
    private var windows: [UUID: NSWindow] = [:]

    func show(_ share: WatchedShare) {
        let window = windows[share.id] ?? makeWindow(for: share)
        windows[share.id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(for share: WatchedShare) -> NSWindow {
        let view = LaunchItemsView(shareID: share.id) { [weak self] in
            self?.launcher?.openNow(share.id)
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(share.displayName) — Open When Mounted"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// The share is no longer watched.
    func close(_ id: UUID) {
        windows.removeValue(forKey: id)?.close()
    }
}

private struct LaunchItemsView: View {
    let shareID: UUID
    let openNow: () -> Void

    @State private var settings = AppSettings.shared
    @State private var isDropTarget = false
    /// Bumped whenever the window comes forward, so apps deleted or moved since it was
    /// last shown are rechecked; the window is kept, not rebuilt.
    @State private var checkedAt = Date()

    private var index: Int? { settings.shares.firstIndex { $0.id == shareID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let index {
                editor(index)
            } else {
                Text("This share is no longer being kept mounted.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
        .id(checkedAt)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            checkedAt = Date()
        }
    }

    @ViewBuilder
    private func editor(_ index: Int) -> some View {
        let share = settings.shares[index]
        Text("When \(share.displayName) mounts, StayMounted opens these apps in order. Apps that are already open are left alone.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Group {
            if share.apps.isEmpty {
                Text("No apps yet. Click Add App… or drag apps here from Finder.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List {
                    ForEach($settings.shares[index].apps) { $item in
                        LaunchItemRow(item: $item) {
                            settings.shares[index].apps.removeAll { $0.id == item.id }
                        }
                    }
                    .onMove { from, to in
                        settings.shares[index].apps.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
                .frame(height: min(CGFloat(share.apps.count) * 40 + 10, 260))
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls, to: index)
            return true
        } isTargeted: { isDropTarget = $0 }

        HStack {
            Button("Add App…") { chooseApps(for: index) }
            Spacer()
            Button("Open Now", action: openNow)
                .disabled(share.apps.isEmpty)
                .help("Open these apps now, as if the share had just mounted")
        }

        Divider()

        Stepper(value: $settings.shares[index].launchDelay, in: 0...120, step: 1) {
            HStack {
                Text("Wait before opening:")
                Text(share.launchDelay == 0 ? "no delay" : "\(share.launchDelay) s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .help("Gives the share a moment to settle before apps that read from it start")
    }

    private func chooseApps(for index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls, to: index)
    }

    private func add(_ urls: [URL], to index: Int) {
        guard settings.shares.indices.contains(index) else { return }
        for url in urls {
            guard let item = LaunchItem(appAt: url) else { continue }
            let apps = settings.shares[index].apps
            let duplicate = apps.contains {
                (item.bundleIdentifier != nil && $0.bundleIdentifier == item.bundleIdentifier) || $0.path == item.path
            }
            guard !duplicate else { continue }
            settings.shares[index].apps.append(item)
            Diagnostics.note("\(settings.shares[index].displayName): will open \(item.name)")
        }
    }
}

private struct LaunchItemRow: View {
    @Binding var item: LaunchItem
    let remove: () -> Void

    var body: some View {
        let url = AppLauncher.location(of: item)
        HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                  ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(url == nil ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).lineLimit(1)
                if url == nil {
                    Text("Not found").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if url == nil {
                Button("Locate…", action: locate).controlSize(.small)
            }
            Toggle("Hidden", isOn: $item.hidden)
                .toggleStyle(.checkbox)
                .help("Open without bringing the app to the front")
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Don't open \(item.name)")
        }
        .padding(.vertical, 2)
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let found = LaunchItem(appAt: url) else { return }
        item.bundleIdentifier = found.bundleIdentifier
        item.path = found.path
        item.name = found.name
    }
}
