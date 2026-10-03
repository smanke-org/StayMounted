import AppKit
import SwiftUI
import StayMountedKit

struct MenuContentView: View {
    let keeper: MountKeeper
    let launchAtLogin: LaunchAtLogin

    @State private var settings = AppSettings.shared
    @State private var updates = UpdateAvailability.shared
    @State private var newAddress = ""
    @State private var addError: String?

    private var mountedCount: Int {
        settings.shares.filter { keeper.status(of: $0).isMounted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if settings.pausedAll {
                pausedBanner
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if keeper.localNetworkBlocked {
                localNetworkNotice
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            watchedSection
            unwatchedSection
            addSection

            Divider().padding(.vertical, 6)
            footer
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .frame(width: 330)
        .onAppear {
            keeper.refreshMounts()
            launchAtLogin.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("StayMounted")
                .font(.headline)
            Spacer()
            if !settings.shares.isEmpty {
                Text("\(mountedCount) of \(settings.shares.count) mounted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
            Text("Remounting is paused.")
                .font(.callout)
            Spacer()
            Button("Resume") { keeper.setPausedAll(false) }
                .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    /// Shares still mount without it, but every attempt has to go to NetFS blind — so an
    /// absent server costs a slow mount timeout instead of a quick check.
    private var localNetworkNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local Network access is off", systemImage: "network.slash")
                .font(.callout)
                .fontWeight(.medium)
            Text("StayMounted can't check whether your servers are answering, so it tries to mount without checking. Allow it in Privacy & Security for quicker reconnects.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Local Network Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    // MARK: - Watched shares

    @ViewBuilder
    private var watchedSection: some View {
        if settings.shares.isEmpty {
            Text(keeper.unwatchedMounts.isEmpty
                 ? "Add a share below and StayMounted will keep it mounted, including after a restart."
                 : "Pick a mounted share below, or add one by address, and StayMounted will keep it mounted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        } else {
            VStack(spacing: 2) {
                ForEach(settings.shares) { share in
                    ShareRow(share: share, status: keeper.status(of: share), keeper: keeper)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var unwatchedSection: some View {
        let unwatched = keeper.unwatchedMounts
        if !unwatched.isEmpty {
            SectionLabel("Also mounted")
            VStack(spacing: 2) {
                ForEach(unwatched) { mount in
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mount.source.share)
                                .lineLimit(1)
                            Text(mount.source.displayHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button("Keep Mounted") { keeper.keepMounted(mount) }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Add a share")
            HStack(spacing: 6) {
                TextField("smb://server/share", text: $newAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: newAddress) { addError = nil }
                Button("Add", action: add)
                    .disabled(newAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func add() {
        switch keeper.add(address: newAddress) {
        case .added:
            newAddress = ""
            addError = nil
        case .invalid:
            addError = "Enter an SMB address such as smb://server/share."
        case .duplicate:
            addError = "That share is already being kept mounted."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuToggle(title: "Pause All Remounting", isOn: Binding(
                get: { settings.pausedAll },
                set: { keeper.setPausedAll($0) }
            ))
            MenuToggle(title: "Ask Before Remounting After Eject", isOn: $settings.confirmAfterEject)
            MenuToggle(title: "Open at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.set($0) }
            ))
            if launchAtLogin.needsApproval {
                MenuButton(title: "Allow in Login Items Settings…", systemImage: "exclamationmark.triangle") {
                    launchAtLogin.openLoginItemsSettings()
                }
            }
            #if !APPSTORE
            // The App Store updates the store build itself, so this only exists here.
            MenuToggle(title: "Check for Updates at Launch", isOn: $settings.checkForUpdatesAtLaunch)
            #endif

            Divider().padding(.vertical, 6)

            #if !APPSTORE
            if let pending = updates.pending {
                MenuButton(title: "Update to \(pending)…", systemImage: "arrow.down.circle.fill") {
                    UpdateController.checkForUpdates()
                }
            } else {
                MenuButton(title: "Check for Updates…", systemImage: nil) {
                    UpdateController.checkForUpdates()
                }
            }
            #endif
            MenuButton(title: "Open Log", systemImage: nil) {
                let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appending(path: "Logs/StayMounted.log")
                NSWorkspace.shared.open(log)
            }
            HStack {
                MenuButton(title: "Quit StayMounted", systemImage: nil) { NSApp.terminate(nil) }
                Text(AppInfo.displayVersion)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
            }
        }
    }
}

// MARK: - Rows

private struct ShareRow: View {
    let share: WatchedShare
    let status: ShareStatus
    let keeper: MountKeeper

    @State private var isHovering = false

    private var statusText: String {
        switch status {
        case .mounted: "Mounted"
        case .checking: "Looking for server…"
        case .mounting: "Mounting…"
        case .waitingForServer: "Waiting for server"
        case .needsSignIn: "Sign in needed"
        case .failed(let message): message
        case .ejectPending: "Ejected — remounting shortly"
        case .paused: "Paused"
        case .pausedAll: "Paused"
        case .notMounted: "Not mounted"
        }
    }

    private var colour: Color {
        switch status {
        case .mounted: .green
        case .checking, .mounting, .ejectPending: .blue
        case .waitingForServer, .notMounted: .orange
        case .needsSignIn, .failed: .red
        case .paused, .pausedAll: .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: status.isMounted
                      ? "externaldrive.connected.to.line.below.fill"
                      : "externaldrive.connected.to.line.below")
                    .foregroundStyle(status.isMounted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Circle()
                    .fill(colour)
                    .frame(width: 7, height: 7)
                    .offset(x: 9, y: 7)
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(share.displayName)
                    .lineLimit(1)
                Text([share.share?.displayHost, statusText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            switch status {
            case .needsSignIn:
                Button("Sign In…") { keeper.mountNow(share, interactive: true) }
                    .controlSize(.small)
            case .waitingForServer, .notMounted, .failed, .ejectPending:
                Button("Mount") { keeper.mountNow(share, interactive: false) }
                    .controlSize(.small)
            case .paused:
                Button("Resume") { keeper.setPaused(share, false) }
                    .controlSize(.small)
            default:
                EmptyView()
            }

            Menu {
                if case .mounted(let point) = status {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: point))
                    }
                } else {
                    Button("Mount Now") { keeper.mountNow(share, interactive: false) }
                    Button("Sign In…") { keeper.mountNow(share, interactive: true) }
                }
                Divider()
                if share.paused {
                    Button("Resume Keeping Mounted") { keeper.setPaused(share, false) }
                } else {
                    Button("Pause") { keeper.setPaused(share, true) }
                }
                Button("Stop Keeping Mounted") { keeper.remove(share) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(share.share?.displayString ?? share.address)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

/// A full-width row that highlights on hover, like a menu item.
private struct MenuButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct MenuToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}
