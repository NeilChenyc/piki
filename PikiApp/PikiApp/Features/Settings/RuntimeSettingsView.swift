import SwiftUI
import TipKit

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
                podcastTranscriptionSection
            }
            .padding(24)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.primaryPanelBackground)
        .task {
            await viewModel.load(appState: appState)
        }
        .sheet(isPresented: $vm.showPresetSheet) {
            PresetFormSheet()
                .environment(viewModel)
        }
        .sheet(isPresented: $vm.showTingwuHelpSheet) {
            TingwuHelpSheet()
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
        .popoverTip(SettingsTip())
    }

    // MARK: - Section 1: Runtime Status

    private var runtimeStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("本地 Runtime 与模型配置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                smokeTestButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricItem(label: "应用", value: "已启动")
                    metricItem(label: "本地 Runtime", value: localRuntimeStatus)
                    metricItem(label: "模型配置", value: modelConfigurationStatus)
                }
                metricItem(label: "Model", value: viewModel.currentModel.isEmpty ? "--" : viewModel.currentModel)
                metricItem(label: "Base URL", value: viewModel.currentBaseURL.isEmpty ? "default" : viewModel.currentBaseURL)
                metricItem(label: "状态", value: appState.runtimeModeTitle)
            }

            if shouldShowOnboardingHint {
                bannerView(.info("本地 Runtime 已就绪。下一步：填写模型、Base URL 和 API Key，然后运行 Smoke Test。"))
            }

            if case .none = viewModel.bannerState {} else {
                bannerView(viewModel.bannerState)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: topCardMinHeight, alignment: .topLeading)
        .cardStyle()
    }

    // MARK: - Section 2: Podcast Transcription

    private var podcastTranscriptionSection: some View {
        @Bindable var vm = viewModel

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("播客转录")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        tingwuStatusPill
                    }
                    Text("配置你自己的阿里云通义听悟账号，小宇宙播客转录会走你的阿里云账号计费。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    viewModel.showTingwuHelpSheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("如何配置播客转录功能")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], alignment: .leading, spacing: 12) {
                tingwuField("AccessKey ID", help: tingwuAccessKeyHint) {
                    TextField("LTAI...", text: $vm.draftAliyunAccessKeyId)
                        .textFieldStyle(.roundedBorder)
                }

                tingwuField("AccessKey Secret", help: viewModel.aliyunAccessKeySecretConfigured ? "留空则保留已有 Secret" : nil) {
                    SecureField("AccessKey Secret", text: $vm.draftAliyunAccessKeySecret)
                        .textFieldStyle(.roundedBorder)
                }

                tingwuField("通义听悟 AppKey", help: tingwuAppKeyHint) {
                    SecureField("项目 AppKey", text: $vm.draftTingwuAppKey)
                        .textFieldStyle(.roundedBorder)
                }

                tingwuField("Region", help: "默认 cn-beijing") {
                    TextField("cn-beijing", text: $vm.draftTingwuRegionId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.saveTingwuConfig(appState: appState) }
                } label: {
                    if viewModel.isSavingTingwuConfig {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存播客转录配置")
                    }
                }
                .controlSize(.large)
                .disabled(!viewModel.canSaveTingwuConfig || !appState.isConnected)

                Button(role: .destructive) {
                    Task { await viewModel.clearTingwuConfig(appState: appState) }
                } label: {
                    if viewModel.isClearingTingwuConfig {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("清空配置")
                    }
                }
                .controlSize(.large)
                .disabled(!viewModel.tingwuConfigured || viewModel.isSavingTingwuConfig || viewModel.isClearingTingwuConfig || !appState.isConnected)

                Spacer()

                Text("保存后，播客任务会先调用通义听悟转录，再交给 Agent 入库。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: - Section 3: Presets

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

    // MARK: - Section 4: Vault

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

    private var tingwuStatusPill: some View {
        Text(viewModel.tingwuConfigured ? "已配置" : "未配置")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(viewModel.tingwuConfigured ? Theme.accentDark : Theme.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(viewModel.tingwuConfigured ? Theme.accentLight : Theme.warning.opacity(0.12))
            .clipShape(.rect(cornerRadius: 5))
    }

    private var tingwuAccessKeyHint: String? {
        guard !viewModel.aliyunAccessKeyIdPreview.isEmpty else { return nil }
        return "当前：\(viewModel.aliyunAccessKeyIdPreview)。留空则保留。"
    }

    private var tingwuAppKeyHint: String? {
        guard !viewModel.tingwuAppKeyPreview.isEmpty else { return nil }
        return "当前：\(viewModel.tingwuAppKeyPreview)。留空则保留。"
    }

    private func tingwuField(_ label: String, help: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            content()
            if let help {
                Text(help)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
        }
    }

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
        .disabled(viewModel.isRunningSmokeTest || viewModel.isApplyingPreset || !appState.isConnected)
    }

    private var localRuntimeStatus: String {
        switch appState.connectionStatus {
        case .connected:
            "已就绪"
        case .starting:
            "启动中"
        case .disconnected, .error:
            "未就绪"
        }
    }

    private var modelConfigurationStatus: String {
        viewModel.apiKeyConfigured ? "已完成" : "待填写"
    }

    private var shouldShowOnboardingHint: Bool {
        appState.isConnected && !viewModel.apiKeyConfigured
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

struct TingwuHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("如何配置播客转录功能")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Piki 会使用你填写的阿里云通义听悟凭证提交离线转写任务，并主动轮询结果；费用由你的阿里云账号承担。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                helpStep("1", "登录阿里云控制台，开通通义听悟服务。")
                helpStep("2", "在 RAM / AccessKey 管理中创建 AccessKey ID 和 AccessKey Secret。")
                helpStep("3", "进入通义听悟控制台，创建或选择一个项目，复制项目 AppKey。")
                helpStep("4", "在 Piki 设置页填入 AccessKey、AppKey 和 Region；默认 Region 使用 cn-beijing。")
                helpStep("5", "Piki 使用主动轮询方式，不需要配置回调地址。")
            }

            HStack(spacing: 12) {
                Link("通义听悟快速入门", destination: URL(string: "https://help.aliyun.com/zh/tingwu/getting-started-1")!)
                Link("音视频文件离线转写", destination: URL(string: "https://help.aliyun.com/zh/tingwu/offline-transcribe-of-audio-and-video-files")!)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(24)
        .frame(width: 520)
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentDark)
                .frame(width: 22, height: 22)
                .background(Theme.accentLight)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
