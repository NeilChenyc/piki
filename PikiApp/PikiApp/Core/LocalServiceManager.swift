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

        if await probeHealth() {
            startMonitoring()
            return
        }

        appState.connectionStatus = .disconnected
        appState.serviceErrorMessage = "Piki Runtime Host is not available."

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
        guard consecutiveFailures >= 2 else { return }
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
