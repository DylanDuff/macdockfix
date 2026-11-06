import SwiftUI

@main
struct MacDockFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacDockFix", systemImage: "dock.rectangle") {
            StatusMenu(coordinator: appDelegate.coordinator)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = DockCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}

private struct StatusMenu: View {
    let coordinator: DockCoordinator

    var body: some View {
        if coordinator.isAccessibilityTrusted {
            Text("Accessibility access granted")
        } else {
            Button("Grant Accessibility Access…") { coordinator.openAccessibilitySettings() }
            Text("Needed to open windows on the clicked display")
        }
        Text("Real Dock is on: \(coordinator.realDockScreenName)")
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { coordinator.launchesAtLogin },
            set: { coordinator.launchesAtLogin = $0 }))
        Divider()
        Button("Quit MacDockFix") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
