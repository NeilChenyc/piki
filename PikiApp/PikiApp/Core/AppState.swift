import SwiftUI

@Observable
@MainActor
final class AppState {
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
        if let path = config.vaultPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                self.vaultPath = url
            } else {
                self.vaultPath = AppState.defaultVaultPath()
            }
        } else {
            self.vaultPath = AppState.defaultVaultPath()
        }
    }

    var hasVault: Bool {
        vaultPath != nil
    }

    var isConnected: Bool {
        connectionStatus == .connected
    }

    var runtimeModeTitle: String {
        guard isConnected else { return "Offline" }
        guard let serviceHealth else { return "Checking runtime" }
        if serviceHealth.agentRuntimeConfigured == true {
            return "Claude Agent"
        }
        if serviceHealth.runnerAvailable == true {
            return "Runtime not configured"
        }
        return "Runtime installed"
    }

    var runtimeModeDetail: String {
        guard isConnected else {
            return serviceErrorMessage ?? "Runtime host is disconnected."
        }
        guard let serviceHealth else {
            return "Checking runtime host..."
        }
        if serviceHealth.agentRuntimeConfigured == true {
            return "Claude Agent runtime is active."
        }
        if serviceHealth.runnerAvailable == true {
            return "Claude runtime is installed but not configured."
        }
        return serviceHealth.runnerDetail ?? "Claude runtime is installed, but the agent SDK is unavailable."
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

    private func persistConfig() {
        appConfig.vaultPath = vaultPath?.path(percentEncoded: false)
        AppConfigStorage.save(appConfig)
    }

    private static func defaultVaultPath() -> URL? {
        let fileManager = FileManager.default
        if let envPath = ProcessInfo.processInfo.environment["PIKI_DEFAULT_VAULT_PATH"], !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath, isDirectory: true)
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }

        let developmentVaultPath = "/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/piki-vault"
        let developmentVaultURL = URL(fileURLWithPath: developmentVaultPath, isDirectory: true)
        if fileManager.fileExists(atPath: developmentVaultURL.path(percentEncoded: false)) {
            return developmentVaultURL
        }

        return nil
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
