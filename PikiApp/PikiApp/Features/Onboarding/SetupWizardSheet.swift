import SwiftUI

struct SetupWizardSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(RuntimeSettingsViewModel.self) private var runtimeVM
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Divider()

            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 520, height: 440)
        .background(Theme.primaryPanelBackground)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.WizardStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == viewModel.currentStep ? Theme.accent : Theme.subtleFill)
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .vault:
            SetupStepVault(viewModel: viewModel)
        case .api:
            SetupStepAPI(viewModel: viewModel)
        case .smokeTest:
            SetupStepSmokeTest(viewModel: viewModel)
        }
    }

    private var navigationBar: some View {
        HStack {
            if viewModel.currentStep.rawValue > 0 {
                Button("上一步") { viewModel.goBack() }
            }
            Spacer()
            Button("跳过") { viewModel.skip() }
                .foregroundStyle(Theme.textSecondary)
            if viewModel.currentStep == .smokeTest {
                Button("完成") {
                    viewModel.completeSetup()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                Button("下一步") { viewModel.advanceStep() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }
}