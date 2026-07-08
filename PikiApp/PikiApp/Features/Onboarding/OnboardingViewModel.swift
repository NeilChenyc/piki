import Foundation
import SwiftUI

@Observable
@MainActor
final class OnboardingViewModel {
    enum WizardStep: Int, CaseIterable {
        case vault = 0
        case api = 1
        case smokeTest = 2

        var title: String {
            switch self {
            case .vault: "知识仓库"
            case .api: "模型配置"
            case .smokeTest: "连通测试"
            }
        }
    }

    var currentStep: WizardStep = .vault
    var showWizard = false

    // Step 1: Vault
    var selectedVaultURL: URL?
    var vaultReady = false
    var isInitializingVault = false

    // Step 2: API
    var apiConfigured = false

    // Step 3: Smoke Test
    var smokeTestPassed: Bool?
    var isRunningSmokeTest = false
    var smokeTestError: String?

    // Use case showcase
    var showcaseDismissed: Bool = false

    func loadShowcaseState() {
        showcaseDismissed = AppConfigStorage.load().onboarding.showcaseDismissed
    }

    func dismissShowcase() {
        showcaseDismissed = true
        var config = AppConfigStorage.load()
        config.onboarding.showcaseDismissed = true
        AppConfigStorage.save(config)
    }

    func shouldShowWizard(config: AppConfig) -> Bool {
        !config.onboarding.setupCompleted && !config.onboarding.setupSkipped
    }

    func shouldPresentWizard(config: AppConfig, forcePresentation: Bool) -> Bool {
        forcePresentation || shouldShowWizard(config: config)
    }

    func advanceStep() {
        guard let next = WizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func goBack() {
        guard let prev = WizardStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    func skip() {
        var config = AppConfigStorage.load()
        config.onboarding.setupSkipped = true
        config.onboarding.setupCompleted = true
        AppConfigStorage.save(config)
        showWizard = false
    }

    func completeSetup() {
        var config = AppConfigStorage.load()
        config.onboarding.setupCompleted = true
        if vaultReady { config.onboarding.completedSteps.insert("vault") }
        if apiConfigured { config.onboarding.completedSteps.insert("api") }
        if smokeTestPassed == true { config.onboarding.completedSteps.insert("smokeTest") }
        AppConfigStorage.save(config)
        showWizard = false
    }

    func checkVaultStatus(at url: URL?) {
        guard let url else {
            vaultReady = false
            return
        }
        selectedVaultURL = url
        let rawInbox = url.appending(path: "raw/inbox")
        vaultReady = FileManager.default.fileExists(atPath: rawInbox.path(percentEncoded: false))
    }

    func initializeVault(at url: URL) async {
        isInitializingVault = true
        defer { isInitializingVault = false }
        do {
            try RuntimeSettingsViewModel.ensureVaultExists(at: url)
            selectedVaultURL = url
            vaultReady = true
        } catch {
            vaultReady = false
        }
    }

    func checkAPIStatus(presets: [ConfigurationPreset]) {
        apiConfigured = !presets.isEmpty
    }

    func runSmokeTest(appState: AppState) async {
        isRunningSmokeTest = true
        smokeTestError = nil
        defer { isRunningSmokeTest = false }
        do {
            let response = try await appState.runtimeService.smokeTestRuntime()
            smokeTestPassed = response.ok
            if !response.ok {
                smokeTestError = response.error ?? "测试未通过"
            }
            await appState.refreshServiceHealth()
        } catch {
            smokeTestPassed = false
            smokeTestError = error.localizedDescription
        }
    }
}
