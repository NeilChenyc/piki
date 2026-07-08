import SwiftUI

struct SetupStepAPI: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(RuntimeSettingsViewModel.self) private var runtimeVM
    @Environment(AppState.self) private var appState

    @State private var draftName = ""
    @State private var draftModel = ""
    @State private var draftBaseURL = "https://api.anthropic.com"
    @State private var draftAPIKey = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("配置模型 API")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Piki 需要调用大模型来处理你的知识资料。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            if viewModel.apiConfigured {
                alreadyConfiguredView
            } else {
                formFields
            }
        }
        .onAppear { checkExistingConfig() }
    }

    private var alreadyConfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.success)
            Text("模型 API 已配置")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("你可以随时在设置中修改配置。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 16)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldRow("配置名称", placeholder: "例如：Claude Sonnet", text: $draftName)
            fieldRow("Model", placeholder: "claude-sonnet-4-20250514", text: $draftModel)
            fieldRow("Base URL", placeholder: "https://api.anthropic.com", text: $draftBaseURL)
            secureFieldRow("API Key", placeholder: "sk-ant-...", text: $draftAPIKey)

            Button(action: saveConfig) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("保存并应用")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canSave || isSaving)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
    }

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func fieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func secureFieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            SecureField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func checkExistingConfig() {
        let presets = PresetStorage.load()
        if !presets.isEmpty {
            viewModel.apiConfigured = true
        }
    }

    private func saveConfig() {
        isSaving = true
        runtimeVM.draftName = draftName.trimmingCharacters(in: .whitespaces)
        runtimeVM.draftModel = draftModel.trimmingCharacters(in: .whitespaces)
        runtimeVM.draftBaseURL = draftBaseURL.trimmingCharacters(in: .whitespaces)
        runtimeVM.draftAPIKey = draftAPIKey.trimmingCharacters(in: .whitespaces)
        runtimeVM.editingPreset = nil
        runtimeVM.savePreset()

        Task {
            if let preset = runtimeVM.presets.last {
                await runtimeVM.applyPreset(preset, appState: appState)
            }
            viewModel.apiConfigured = true
            isSaving = false
        }
    }
}
