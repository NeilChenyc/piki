import SwiftUI

@Observable
@MainActor
final class AppState {
    var selectedTab: SidebarTab = .home
    var vaultPath: URL? = AppState.defaultVaultPath()
    var serviceBaseURL: URL = URL(string: "http://127.0.0.1:8000")!
    var connectionStatus: ServiceConnectionStatus = .disconnected
    var serviceErrorMessage: String?
    var serviceHealth: ServiceHealth?

    @ObservationIgnored let apiClient = APIClient()
    @ObservationIgnored var serviceManager: LocalServiceManager?

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
        return "Runtime unavailable"
    }

    var runtimeModeDetail: String {
        guard isConnected else {
            return serviceErrorMessage ?? "Agent Service is disconnected."
        }
        guard let serviceHealth else {
            return "Checking Agent Service runtime..."
        }
        if serviceHealth.agentRuntimeConfigured == true {
            return "Claude Agent runtime is active."
        }
        if serviceHealth.runnerAvailable == true {
            return "Claude runtime is installed but not configured."
        }
        return serviceHealth.runnerDetail ?? "Agent runtime is unavailable."
    }

    func updateServiceBaseURL(_ url: URL) {
        serviceBaseURL = url
        apiClient.baseURL = url
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Today"
        case .inbox: "Inbox"
        case .wiki: "Wiki"
        case .health: "Health"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .inbox: "tray.fill"
        case .wiki: "book.fill"
        case .health: "heart.text.square.fill"
        }
    }
}
