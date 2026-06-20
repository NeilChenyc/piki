import Foundation

@MainActor
final class LocalServiceManager {
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?
    private var process: Process?
    private var launchedProcess = false
    private var restartAttempted = false
    private var consecutiveFailures = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func start() async {
        appState.connectionStatus = .starting
        appState.serviceErrorMessage = nil
        appState.apiClient.baseURL = appState.serviceBaseURL

        if await probeHealth() {
            startMonitoring()
            return
        }

        if launchBundledService() {
            await waitForReadiness()
        } else {
            appState.connectionStatus = .disconnected
            appState.serviceErrorMessage = "Agent Service is not running. For development, start it with uvicorn on 127.0.0.1:8000."
        }

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

        guard launchedProcess, let process else { return }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        launchedProcess = false
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
        guard launchedProcess, consecutiveFailures >= 2, !restartAttempted else { return }

        restartAttempted = true
        stopLaunchedProcess()
        if launchBundledService() {
            await waitForReadiness()
        }
    }

    private func waitForReadiness() async {
        appState.connectionStatus = .starting
        for _ in 0..<12 {
            if await probeHealth() {
                consecutiveFailures = 0
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        appState.connectionStatus = .error
        appState.serviceErrorMessage = "Agent Service was started but did not become ready on 127.0.0.1:8000."
    }

    private func probeHealth() async -> Bool {
        do {
            let health = try await appState.apiClient.health()
            appState.applyServiceHealth(health)
            return health.ok
        } catch {
            appState.markServiceDisconnected(message: error.localizedDescription)
            return false
        }
    }

    private func launchBundledService() -> Bool {
        guard let executableURL = bundledServiceExecutableURL(),
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            return false
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--host", "127.0.0.1", "--port", "8000"]
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PIKI_APP_MANAGED_SERVICE": "1"],
            uniquingKeysWith: { _, new in new }
        )

        do {
            try process.run()
            self.process = process
            launchedProcess = true
            return true
        } catch {
            appState.connectionStatus = .error
            appState.serviceErrorMessage = "Failed to start bundled Agent Service: \(error.localizedDescription)"
            return false
        }
    }

    private func stopLaunchedProcess() {
        guard launchedProcess, let process else { return }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        launchedProcess = false
    }

    private func bundledServiceExecutableURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: "piki-agent-service",
            withExtension: nil,
            subdirectory: "agent-service"
        ) {
            return url
        }
        return Bundle.main.resourceURL?
            .appendingPathComponent("agent-service", isDirectory: true)
            .appendingPathComponent("piki-agent-service")
    }
}
