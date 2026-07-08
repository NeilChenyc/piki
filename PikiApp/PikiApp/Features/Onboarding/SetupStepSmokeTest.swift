import SwiftUI

struct SetupStepSmokeTest: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("运行连通测试")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("验证模型 API 是否可以正常调用。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            Spacer().frame(height: 8)

            resultView

            if viewModel.smokeTestPassed != true {
                Button(action: runTest) {
                    if viewModel.isRunningSmokeTest {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("测试中...")
                        }
                    } else {
                        Label("运行 Smoke Test", systemImage: "play.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(viewModel.isRunningSmokeTest)
            }

            Spacer()

            skipHint
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    @ViewBuilder
    private var resultView: some View {
        if let passed = viewModel.smokeTestPassed {
            if passed {
                Label("测试通过，一切就绪！", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.success)
            } else {
                VStack(spacing: 6) {
                    Label("测试未通过", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.error)
                    if let error = viewModel.smokeTestError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private var skipHint: some View {
        Text("跳过此步后，可随时在设置中运行测试。")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
    }

    private func runTest() {
        Task {
            await viewModel.runSmokeTest(appState: appState)
        }
    }
}
