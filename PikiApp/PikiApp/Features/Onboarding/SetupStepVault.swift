import SwiftUI

struct SetupStepVault: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 8) {
                Text("确认知识仓库")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Piki 需要一个本地文件夹来存放你的知识库数据。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            vaultPathSection

            if viewModel.vaultReady {
                Label("仓库已就绪", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { checkVaultStatus() }
    }

    private var vaultPathSection: some View {
        VStack(spacing: 12) {
            if let url = viewModel.selectedVaultURL {
                Text(url.path(percentEncoded: false))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 380)
                    .background(Theme.subtleFill)
                    .clipShape(.rect(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Button("选择其他文件夹") { chooseVault() }
                    .buttonStyle(.bordered)

                if !viewModel.vaultReady {
                    Button("初始化") {
                        Task { await initializeVault() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(viewModel.isInitializingVault)
                }
            }
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择知识仓库所在文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.selectedVaultURL = url
        appState.vaultPath = url
        checkVaultStatus()
    }

    private func initializeVault() async {
        guard let url = viewModel.selectedVaultURL else { return }
        await viewModel.initializeVault(at: url)
    }

    private func checkVaultStatus() {
        let url = viewModel.selectedVaultURL ?? appState.vaultPath
        viewModel.selectedVaultURL = url
        if let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            viewModel.vaultReady = true
        }
    }
}
