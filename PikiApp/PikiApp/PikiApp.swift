import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var serviceManager: LocalServiceManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            serviceManager?.stop()
        }
    }
}

@main
struct PikiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var didStartService = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    guard !didStartService else { return }
                    didStartService = true
                    let manager = LocalServiceManager(appState: appState)
                    appState.serviceManager = manager
                    appDelegate.serviceManager = manager
                    await manager.start()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
