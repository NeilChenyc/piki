import SwiftUI
import AppKit
import TipKit

enum AppLaunchOptions {
    static let forceOnboardingKey = "PIKI_FORCE_ONBOARDING"

    static func shouldForceOnboarding(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
#if DEBUG
        environment[forceOnboardingKey] == "1"
#else
        false
#endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var serviceManager: LocalServiceManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceManager?.stop()
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
    @State private var onboardingViewModel = OnboardingViewModel()
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
                .environment(onboardingViewModel)
                .preferredColorScheme(.light)
                .task {
                    guard !didStartService else { return }
                    didStartService = true
                    appState.prepareDefaultVaultIfNeeded()
                    let manager = LocalServiceManager(appState: appState)
                    appState.serviceManager = manager
                    appDelegate.serviceManager = manager
                    await manager.start()
                    await appState.prewarmHealthLintIfNeeded()
                    try? Tips.configure([
                        .displayFrequency(.daily),
                        .datastoreLocation(.applicationDefault)
                    ])
                    let config = AppConfigStorage.load()
                    let forceOnboarding = AppLaunchOptions.shouldForceOnboarding()
                    onboardingViewModel.loadShowcaseState()
                    if onboardingViewModel.shouldPresentWizard(
                        config: config,
                        forcePresentation: forceOnboarding
                    ) {
                        onboardingViewModel.currentStep = .vault
                        onboardingViewModel.selectedVaultURL = appState.vaultPath
                        onboardingViewModel.vaultReady = appState.vaultPath != nil
                        onboardingViewModel.apiConfigured = runtimeSettingsViewModel.apiKeyConfigured
                        onboardingViewModel.showWizard = true
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.automatic)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
