import AppKit
import SwiftUI

/// StayMounted's settings. The shares themselves stay in the menu bar panel (or its
/// window); everything here is a preference.
struct SettingsView: View {
    let launchAtLogin: LaunchAtLogin

    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open StayMounted at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled || launchAtLogin.needsApproval },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    LabeledContent {
                        Button("Open Login Items Settings") { launchAtLogin.openLoginItemsSettings() }
                    } label: {
                        Label("It's switched off in Login Items, so shares won't come back after a restart.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Toggle("Ask before remounting a share I ejected", isOn: $settings.confirmAfterEject)
                Text("Off remounts an ejected share right away, as if the network had dropped it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock and menu bar") {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .help("Adds a Dock icon whose right-click menu opens Settings.")
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                if !settings.showInDock && !settings.showInMenuBar {
                    Text(AppPresence.hiddenEverywhereNote(appName: "StayMounted", settingsName: "its shares in a window"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            #if APPSTORE
            Section {
                LabeledContent("Version", value: AppInfo.displayVersion)
            }
            #else
            // The App Store updates the store build itself, and the sandbox can't reach
            // iCloud Drive, so these only exist here.
            SyncUpdateSections()
            #endif
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
