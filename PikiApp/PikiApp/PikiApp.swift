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
    @State private var homeViewModel = HomeViewModel()
    @State private var wikiViewModel = WikiViewModel()
    @State private var inboxViewModel = InboxViewModel()
    @State private var healthViewModel = HealthViewModel()
    @State private var runtimeSettingsViewModel = RuntimeSettingsViewModel()
    @State private var didStartService = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(homeViewModel)
                .environment(wikiViewModel)
                .environment(inboxViewModel)
                .environment(healthViewModel)
                .environment(runtimeSettingsViewModel)
                .preferredColorScheme(.light)
                .task {
                    guard !didStartService else { return }
                    didStartService = true
                    let manager = LocalServiceManager(appState: appState)
                    appState.serviceManager = manager
                    appDelegate.serviceManager = manager
                    await manager.start()
                    await appState.prewarmHealthLintIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
