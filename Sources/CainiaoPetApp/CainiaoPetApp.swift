import AppKit
import SwiftUI

@main
struct CainiaoPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("CainiaoPet Command Center", id: "control-center") {
            ControlCenterView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 680)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("CainiaoPet", systemImage: "pawprint.fill") {
            Button("Open Command Center") {
                AppDelegate.showControlCenter()
            }

            Divider()

            Button("Feed") { model.perform(.feed) }
            Button("Play") { model.perform(.play) }
            Button(model.pet.isSleeping ? "Wake Up" : "Sleep") {
                model.perform(.sleepOrWake)
            }

            Divider()

            Toggle(
                "Show Floating Pet",
                isOn: Binding(
                    get: { model.isPetVisible },
                    set: { model.setPetVisible($0) }
                )
            )

            Divider()

            Button("Quit CainiaoPet") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPetPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        panelController = FloatingPetPanelController(model: AppModel.shared)
        panelController?.show()
    }

    static func showControlCenter() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let candidate = NSApplication.shared.windows.first {
            !($0 is NSPanel) && $0.title == "CainiaoPet Command Center"
        } ?? NSApplication.shared.windows.first { !($0 is NSPanel) }
        candidate?.makeKeyAndOrderFront(nil)
    }
}
