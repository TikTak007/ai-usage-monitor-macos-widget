import AppKit
import CodexUsageShared
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearanceRawValue = AppearanceMode.system.rawValue

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(model: appDelegate.model)
                .preferredColorScheme(appearanceMode.colorScheme)
        } label: {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 18, height: 18)
                .fixedSize()
                .accessibilityLabel("AI usage")
        }
        .menuBarExtraStyle(.window)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(storedValue: appearanceRawValue)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageViewModel()
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showsPreviewWindow = CommandLine.arguments.contains("--preview-window")
        NSApp.setActivationPolicy(showsPreviewWindow ? .regular : .accessory)
        WidgetSnapshotServer.shared.start()
        model.start()

        guard showsPreviewWindow else { return }
        let controller = NSHostingController(rootView: UsagePanel(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "AI Usage Monitor"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }
}
