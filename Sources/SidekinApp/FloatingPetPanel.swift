import AppKit
import SwiftUI

@MainActor
final class FloatingPetPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: NSPanel

    init(model: AppModel) {
        self.model = model

        let size = NSSize(width: 235, height: 265)
        self.panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: FloatingPetView(model: model))
        restorePosition(for: size)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibilityChanged(_:)),
            name: .sidekinVisibilityChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        UserDefaults.standard.set(origin.x, forKey: "floatingPetX")
        UserDefaults.standard.set(origin.y, forKey: "floatingPetY")
    }

    @objc private func visibilityChanged(_ notification: Notification) {
        let visible = (notification.object as? NSNumber)?.boolValue ?? true
        visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
    }

    private func restorePosition(for size: NSSize) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "floatingPetX") != nil,
           defaults.object(forKey: "floatingPetY") != nil {
            panel.setFrameOrigin(NSPoint(
                x: defaults.double(forKey: "floatingPetX"),
                y: defaults.double(forKey: "floatingPetY")
            ))
            return
        }

        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - 28,
            y: frame.minY + 42
        ))
    }
}

private struct FloatingPetView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 2) {
            statusPill

            PetAvatarView(
                stage: model.displayedStage,
                theme: model.activeTheme,
                customAssetURL: model.displayedAssetURL,
                activity: model.pet.codexActivity,
                isSleeping: model.pet.isSleeping,
                size: 205
            )
            .frame(width: 215, height: 215)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            AppDelegate.showControlCenter()
        }
        .contextMenu {
            Button("Open Command Center") { AppDelegate.showControlCenter() }
            Divider()
            Button("Feed") { model.perform(.feed) }
            Button("Play") { model.perform(.play) }
            Button(model.pet.isSleeping ? "Wake Up" : "Sleep") {
                model.perform(.sleepOrWake)
            }
            Divider()
            Button("Hide Desktop Pet") { model.setPetVisible(false) }
        }
        .accessibilityLabel("Sidekin floating companion. Double-click to open the Command Center.")
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(model.pet.isSleeping ? "Sleeping" : model.pet.codexActivity.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.54), in: Capsule())
    }

    private var statusColor: Color {
        if model.pet.isSleeping { return .indigo }
        switch model.pet.codexActivity {
        case .idle: return Color.mint
        case .running: return Color.cyan
        case .completed: return Color.green
        case .failed: return Color.orange
        }
    }
}
