import SwiftUI

struct RuntimeSettingsView: View {
    private let topCardMinHeight: CGFloat = 190

    @Environment(AppState.self) private var appState
    @Environment(RuntimeSettingsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 16) {
                    runtimeStatusSection
                    vaultSection
                }
                presetsSection
            }
            .padding(24)
            .padding(.top, 16)
        }
        .background(Theme.primaryPanelBackground)
        .task {
            await viewModel.load(appState: appState)
        }
        .sheet(isPresented: $vm.showPresetSheet) {
            PresetFormSheet()
                .environment(viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("管理运行时配置、切换大模型 API 配置模板、设置知识仓库路径。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Section 1: Runtime Status

    private var runtimeStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("当前接入大模型 API")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                smokeTestButton
            }

            VStack(alignment: .leading, spacing: 10) {
                metricItem(label: "Model", value: viewModel.currentModel.isEmpty ? "--" : viewModel.currentModel)
                metricItem(label: "Base URL", value: viewModel.currentBaseURL.isEmpty ? "default" : viewModel.currentBaseURL)
                metricItem(label: "状态", value: appState.runtimeModeTitle)
            }

            if case .none = viewModel.bannerState {} else {
                bannerView(viewModel.bannerState)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: topCardMinHeight, alignment: .topLeading)
        .cardStyle()
    }

    // MARK: - Section 2: Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("大模型 API 配置模板")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { viewModel.prepareNewPreset() } label: {
                    Label("添加配置", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            if viewModel.presets.isEmpty {
                emptyPresetsPlaceholder
            } else {
                presetGrid
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var emptyPresetsPlaceholder: some View {
        VStack(spacing: 8) {
            Text("暂无保存的配置模板")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            Text("点击「添加配置」保存一组运行时配置以便快速切换。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(viewModel.presets) { preset in
                PresetCard(
                    preset: preset,
                    isActive: preset.id == viewModel.activePresetId,
                    onApply: { Task { await viewModel.applyPreset(preset, appState: appState) } },
                    onEdit: { viewModel.prepareEditPreset(preset) },
                    onDelete: { viewModel.deletePreset(id: preset.id) }
                )
            }
        }
    }

    // MARK: - Section 3: Vault

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("知识仓库")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.textTertiary)
                    Text(appState.vaultPath?.path(percentEncoded: false) ?? "未选择仓库路径")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("选择路径...") { chooseVault() }
                    .controlSize(.large)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    guard let url = appState.vaultPath else { return }
                    Task { await viewModel.initializeVault(at: url) }
                } label: {
                    if viewModel.isInitializingVault {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("初始化仓库")
                    }
                }
                .controlSize(.large)
                .disabled(appState.vaultPath == nil || viewModel.isInitializingVault)

                if let msg = viewModel.vaultInitMessage {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: topCardMinHeight, alignment: .topLeading)
        .cardStyle()
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .starting: Theme.warning
        case .connected: Theme.success
        case .disconnected: Theme.error
        case .error: Theme.error
        }
    }

    private var smokeTestButton: some View {
        Button {
            Task { await viewModel.runSmokeTest(appState: appState) }
        } label: {
            if viewModel.isRunningSmokeTest {
                ProgressView().controlSize(.small)
            } else {
                Text("Smoke Test").font(.system(size: 12))
            }
        }
        .disabled(viewModel.isRunningSmokeTest || viewModel.isApplyingPreset)
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bannerView(_ state: RuntimeSettingsViewModel.BannerState) -> some View {
        let (bgColor, fgColor, message): (Color, Color, String) = switch state {
        case .none: (Theme.subtleFill, Theme.textSecondary, "")
        case .info(let m): (Theme.selection, Theme.textSecondary, m)
        case .success(let m): (Theme.accentLight, Theme.accentDark, m)
        case .error(let m): (Color.red.opacity(0.08), Theme.error, m)
        }

        return Text(message)
            .font(.system(size: 12))
            .foregroundStyle(fgColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(bgColor)
            .clipShape(.rect(cornerRadius: 8))
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择你的 Piki 知识仓库目录"
        if panel.runModal() == .OK, let url = panel.url {
            appState.vaultPath = url
            viewModel.vaultInitMessage = nil
        }
    }
}
