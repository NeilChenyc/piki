import SwiftUI

struct PresetFormSheet: View {
    @Environment(RuntimeSettingsViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 20) {
            Text(viewModel.editingPreset == nil ? "新建配置" : "编辑配置")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                fieldSection("名称") {
                    TextField("例如：Claude Sonnet 生产环境", text: $vm.draftName)
                        .textFieldStyle(.roundedBorder)
                }

                fieldSection("Model") {
                    TextField("claude-sonnet-4-20250514", text: $vm.draftModel)
                        .textFieldStyle(.roundedBorder)
                }

                fieldSection("Anthropic Base URL") {
                    TextField("https://api.anthropic.com", text: $vm.draftBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                fieldSection("API Key") {
                    SecureField("sk-ant-...", text: $vm.draftAPIKey)
                        .textFieldStyle(.roundedBorder)
                    if viewModel.editingPreset != nil {
                        Text("留空则保留原有 Key")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    viewModel.savePreset()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSavePreset)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func fieldSection(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}
