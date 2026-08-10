import AppKit
import SwiftUI

@main
struct CainiaoPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("芽芽战备舱", id: "control-center") {
            ControlCenterView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 680)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("芽芽", systemImage: "pawprint.fill") {
            Button("打开战备舱") {
                AppDelegate.showControlCenter()
            }

            Divider()

            Button("喂食") { model.perform(.feed) }
            Button("玩耍") { model.perform(.play) }
            Button(model.pet.isSleeping ? "唤醒" : "睡觉") {
                model.perform(.sleepOrWake)
            }

            Divider()

            Toggle(
                "显示浮动桌宠",
                isOn: Binding(
                    get: { model.isPetVisible },
                    set: { model.setPetVisible($0) }
                )
            )

            Divider()

            Button("退出芽芽") {
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
            !($0 is NSPanel) && $0.title == "芽芽战备舱"
        } ?? NSApplication.shared.windows.first { !($0 is NSPanel) }
        candidate?.makeKeyAndOrderFront(nil)
    }
}
