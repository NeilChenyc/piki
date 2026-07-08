import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Onboarding logic")
struct OnboardingTests {
    @Test
    func freshConfigShowsWizard() {
        let vm = OnboardingViewModel()
        let config = AppConfig()
        #expect(vm.shouldShowWizard(config: config) == true)
    }

    @Test
    func completedConfigHidesWizard() {
        let vm = OnboardingViewModel()
        var config = AppConfig()
        config.onboarding.setupCompleted = true
        #expect(vm.shouldShowWizard(config: config) == false)
    }

    @Test
    func completedConfigRemainsHiddenWithoutForcePresentation() {
        let vm = OnboardingViewModel()
        var config = AppConfig()
        config.onboarding.setupCompleted = true

        #expect(vm.shouldPresentWizard(config: config, forcePresentation: false) == false)
    }

    @Test
    func forcePresentationOverridesCompletedConfig() {
        let vm = OnboardingViewModel()
        var config = AppConfig()
        config.onboarding.setupCompleted = true

        #expect(vm.shouldPresentWizard(config: config, forcePresentation: true) == true)
    }

    @Test
    func forcePresentationDoesNotMutateConfig() {
        let vm = OnboardingViewModel()
        var config = AppConfig()
        config.onboarding.setupCompleted = true
        let original = config

        _ = vm.shouldPresentWizard(config: config, forcePresentation: true)

        #expect(config == original)
    }

    @Test
    func skippedConfigHidesWizard() {
        let vm = OnboardingViewModel()
        var config = AppConfig()
        config.onboarding.setupSkipped = true
        #expect(vm.shouldShowWizard(config: config) == false)
    }

    @Test
    func advanceAndBackNavigation() {
        let vm = OnboardingViewModel()
        #expect(vm.currentStep == .vault)

        vm.advanceStep()
        #expect(vm.currentStep == .api)

        vm.advanceStep()
        #expect(vm.currentStep == .smokeTest)

        // Guard: no further step
        vm.advanceStep()
        #expect(vm.currentStep == .smokeTest)

        vm.goBack()
        #expect(vm.currentStep == .api)

        vm.goBack()
        #expect(vm.currentStep == .vault)

        // Guard: no step below vault
        vm.goBack()
        #expect(vm.currentStep == .vault)
    }

    @Test
    func useCaseItemsWellFormed() {
        let items = UseCaseItem.allCases
        #expect(items.count == 3)
        for item in items {
            #expect(!item.id.isEmpty)
            #expect(!item.icon.isEmpty)
            #expect(!item.title.isEmpty)
            #expect(!item.starterPrompt.isEmpty)
        }
    }

    @Test
    func appConfigDecodesLegacyJSONWithoutOnboarding() throws {
        let legacyJSON = """
        {
            "vaultPath": "/tmp/vault",
            "activePresetId": "abc"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)
        #expect(config.vaultPath == "/tmp/vault")
        #expect(config.onboarding.setupCompleted == false)
        #expect(config.onboarding.setupSkipped == false)
        #expect(config.onboarding.showcaseDismissed == false)
        #expect(config.onboarding.completedSteps.isEmpty)
    }

    @Test
    func vaultReadyDetection() {
        let vm = OnboardingViewModel()
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "piki-onboard-\(UUID().uuidString)", directoryHint: .isDirectory)

        vm.checkVaultStatus(at: tmp)
        #expect(vm.vaultReady == false)

        try? FileManager.default.createDirectory(
            at: tmp.appending(path: "raw/inbox"),
            withIntermediateDirectories: true
        )
        vm.checkVaultStatus(at: tmp)
        #expect(vm.vaultReady == true)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test
    func forceOnboardingLaunchOptionReadsEnabledValue() {
        #expect(AppLaunchOptions.shouldForceOnboarding(environment: ["PIKI_FORCE_ONBOARDING": "1"]) == true)
        #expect(AppLaunchOptions.shouldForceOnboarding(environment: ["PIKI_FORCE_ONBOARDING": "true"]) == false)
        #expect(AppLaunchOptions.shouldForceOnboarding(environment: [:]) == false)
    }
}
