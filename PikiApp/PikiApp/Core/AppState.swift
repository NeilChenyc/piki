import SwiftUI

@Observable
@MainActor
final class AppState {
    static let defaultVaultDirectoryName = "Piki Vault"

    struct CachedLintResult {
        let result: LintResultDTO
        let receivedAt: Date
    }

    var selectedTab: SidebarTab = .home
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var vaultPath: URL? { didSet { persistConfig() } }
    var connectionStatus: ServiceConnectionStatus = .disconnected
    var serviceErrorMessage: String?
    var serviceHealth: ServiceHealth?
    var cachedLintResult: CachedLintResult?
    private var autoLintPrewarmedVaultPaths: Set<String> = []

    @ObservationIgnored var runtimeService: RuntimeServiceProtocol
    @ObservationIgnored var serviceManager: LocalServiceManager?
    @ObservationIgnored private var appConfig: AppConfig

    init(runtimeService: RuntimeServiceProtocol? = nil) {
        let config = AppConfigStorage.load()
        self.appConfig = config
        self.runtimeService = runtimeService ?? RuntimeServiceFactory.makeDefault()
        let defaultVaultURL = AppState.preferredDefaultVaultURL()
        let environmentOverridesVault = ProcessInfo.processInfo.environment["PIKI_DEFAULT_VAULT_PATH"]?.isEmpty == false
        if environmentOverridesVault {
            self.vaultPath = defaultVaultURL
        } else if let path = config.vaultPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                self.vaultPath = url
            } else {
                self.vaultPath = defaultVaultURL
            }
        } else {
            self.vaultPath = defaultVaultURL
        }
    }

    var hasVault: Bool {
        vaultPath != nil
    }

    var isConnected: Bool {
        connectionStatus == .connected
    }

    var runtimeModeTitle: String {
        guard isConnected else { return "等待 Runtime" }
        guard let serviceHealth else { return "检查 Runtime 中" }
        if serviceHealth.agentRuntimeConfigured == true {
            return "模型已就绪"
        }
        if serviceHealth.runnerAvailable == true {
            return "待配置模型"
        }
        return "Runtime 可用"
    }

    var runtimeModeDetail: String {
        guard isConnected else {
            return serviceErrorMessage ?? "本地 Runtime 尚未连接。"
        }
        guard let serviceHealth else {
            return "正在检查本地 Runtime..."
        }
        if serviceHealth.agentRuntimeConfigured == true {
            return "本地 Runtime 已就绪，模型配置已完成。"
        }
        if serviceHealth.runnerAvailable == true {
            return "本地 Runtime 已就绪，请前往设置填写模型、Base URL 和 API Key。"
        }
        return serviceHealth.runnerDetail ?? "本地 Runtime 可用，但 Agent SDK 尚未准备好。"
    }

    func refreshServiceHealth() async {
        do {
            let health = try await runtimeService.health()
            applyServiceHealth(health)
        } catch {
            markServiceDisconnected(message: error.localizedDescription)
        }
    }

    func applyServiceHealth(_ health: ServiceHealth) {
        serviceHealth = health
        connectionStatus = health.ok ? .connected : .error
        serviceErrorMessage = health.ok ? nil : "Runtime host health check returned ok=false."
    }

    func markServiceDisconnected(message: String) {
        serviceHealth = nil
        connectionStatus = .disconnected
        serviceErrorMessage = message
    }

    func cacheLintResult(_ result: LintResultDTO, receivedAt: Date = Date()) {
        cachedLintResult = CachedLintResult(result: result, receivedAt: receivedAt)
    }

    func prewarmHealthLintIfNeeded() async {
        guard isConnected else { return }
        guard let vaultPath = vaultPath?.path(percentEncoded: false) else { return }
        guard autoLintPrewarmedVaultPaths.contains(vaultPath) == false else { return }

        autoLintPrewarmedVaultPaths.insert(vaultPath)
        do {
            let result = try await runtimeService.runLint(vaultPath: vaultPath)
            cacheLintResult(result)
        } catch {
            autoLintPrewarmedVaultPaths.remove(vaultPath)
        }
    }

    func prepareDefaultVaultIfNeeded() {
        let targetURL = vaultPath ?? Self.preferredDefaultVaultURL()
        vaultPath = targetURL
        do {
            try RuntimeSettingsViewModel.ensureVaultExists(at: targetURL)
        } catch {
            serviceErrorMessage = "默认知识库初始化失败：\(error.localizedDescription)"
        }
    }

    private func persistConfig() {
        appConfig.vaultPath = vaultPath?.path(percentEncoded: false)
        AppConfigStorage.save(appConfig)
    }

    static func preferredDefaultVaultURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        if let envPath = processInfo.environment["PIKI_DEFAULT_VAULT_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true)
        }
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appending(path: defaultVaultDirectoryName, directoryHint: .isDirectory)
        }
        return fileManager.homeDirectoryForCurrentUser.appending(path: defaultVaultDirectoryName, directoryHint: .isDirectory)
    }
}

enum ServiceConnectionStatus: String {
    case starting
    case connected
    case disconnected
    case error

    var title: String {
        switch self {
        case .starting: "Starting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case home
    case inbox
    case wiki
    case health
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .inbox: "资料箱"
        case .wiki: "Wiki"
        case .health: "知识库健康"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .inbox: "tray.fill"
        case .wiki: "book.fill"
        case .health: "heart.text.square.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}
