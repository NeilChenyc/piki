import Foundation

@MainActor
final class LocalServiceManager {
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func start() async {
        appState.connectionStatus = .starting
        appState.serviceErrorMessage = nil

        for _ in 0..<5 {
            if await probeHealth() {
                startMonitoring()
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }

        appState.connectionStatus = .starting
        appState.serviceErrorMessage = "Piki runtime host is preparing."

        startMonitoring()
    }

    func testConnection() async {
        appState.connectionStatus = .starting
        appState.serviceErrorMessage = nil
        _ = await probeHealth()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self, !Task.isCancelled else { return }
                await self.checkAndRecover()
            }
        }
    }

    private func checkAndRecover() async {
        if await probeHealth() {
            consecutiveFailures = 0
            return
        }

        consecutiveFailures += 1
        if consecutiveFailures <= 3 {
            appState.connectionStatus = .starting
            appState.serviceErrorMessage = "Piki runtime host is reconnecting."
            return
        }
        appState.connectionStatus = .disconnected
        appState.serviceErrorMessage = "Piki runtime host is unavailable."
    }

    private func probeHealth() async -> Bool {
        do {
            let health = try await appState.runtimeService.health()
            appState.applyServiceHealth(health)
            return health.ok
        } catch {
            appState.markServiceDisconnected(message: error.localizedDescription)
            return false
        }
    }
}
