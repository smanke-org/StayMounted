import AppKit
import SwiftUI

/// Shown when a watched share is ejected while the network is fine — which almost always
/// means by hand. Remounting immediately would make Eject look broken, so this counts down
/// with a way to keep it ejected, then remounts.
///
/// A panel the app draws itself rather than a notification: macOS hides a banner's buttons
/// behind an "Options" menu unless the user switches the app to Alerts, and the point here
/// is a one-click answer. It never takes focus, so it cannot steal typing.
@MainActor
final class EjectGracePanel {
    var onRemount: ((Set<UUID>) -> Void)?
    var onKeepEjected: ((Set<UUID>) -> Void)?

    private var panel: NSPanel?
    private var countdown: Task<Void, Never>?
    private var pending: Set<UUID> = []

    static let seconds = 10

    /// Shows (or refreshes, if already up) the countdown for these shares.
    func present(_ shares: [WatchedShare]) {
        pending = Set(shares.map(\.id))
        let names = shares.map(\.displayName)
        let deadline = Date().addingTimeInterval(TimeInterval(Self.seconds))
        let ids = pending

        let view = EjectGraceView(
            title: names.count == 1 ? "\(names[0]) was ejected" : "\(names.count) shares were ejected",
            detail: names.count == 1 ? nil : names.joined(separator: ", "),
            deadline: deadline,
            remount: { [weak self] in
                Diagnostics.note("eject grace: remount now")
                self?.dismiss()
                self?.onRemount?(ids)
            },
            keep: { [weak self] in
                Diagnostics.note("eject grace: keep ejected")
                self?.dismiss()
                self?.onKeepEjected?(ids)
            }
        )
        show(view)

        countdown?.cancel()
        countdown = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.seconds))
            guard !Task.isCancelled, let self else { return }
            Diagnostics.note("eject grace: countdown over, remounting")
            self.dismiss()
            self.onRemount?(ids)
        }
    }

    func dismiss() {
        countdown?.cancel()
        countdown = nil
        panel?.orderOut(nil)
        panel = nil
        pending = []
    }

    private func show(_ view: EjectGraceView) {
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Top right, just under the menu bar, where a notification would appear.
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: area.maxX - hosting.fittingSize.width - 16,
                y: area.maxY - hosting.fittingSize.height - 12
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct EjectGraceView: View {
    let title: String
    let detail: String?
    let deadline: Date
    let remount: () -> Void
    let keep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                Text("StayMounted will mount it again in \(left) s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Equal weight, colour says which is which. Drawn rather than tinted: a panel
            // that never takes focus renders standard buttons in their inactive grey.
            HStack(spacing: 8) {
                PanelButton(title: "Remount now", systemImage: "arrow.clockwise.circle.fill",
                            colour: .accentColor, filled: true, action: remount)
                PanelButton(title: "Keep ejected", systemImage: "eject.circle.fill",
                            colour: .secondary, filled: false, action: keep)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}

private struct PanelButton: View {
    let title: String
    let systemImage: String
    let colour: Color
    let filled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    filled ? AnyShapeStyle(colour) : AnyShapeStyle(.quaternary),
                    in: .capsule
                )
                .brightness(isHovering ? (filled ? 0.06 : 0.03) : 0)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
