import Foundation
import os

@MainActor
final class LocalServiceManager {
    private static let logger = Logger(subsystem: "com.piki.app", category: "ServiceManager")
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?
    private var process: Process?
    private var launchedProcess = false
    private var consecutiveFailures = 0
    private var restartCount = 0
    private let maxRestarts = 3

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

        if launchAgentService() {
            await waitForReadiness()
        } else {
            appState.connectionStatus = .starting
            appState.serviceErrorMessage = "Preparing Agent Service..."
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
        stopProcess()
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

        if consecutiveFailures <= 2 {
            appState.connectionStatus = .starting
            appState.serviceErrorMessage = "Agent Service reconnecting..."
            return
        }

        if launchedProcess, restartCount < maxRestarts {
            Self.logger.warning("Agent Service unresponsive, restarting (attempt \(self.restartCount + 1))")
            stopProcess()
            restartCount += 1
            if launchAgentService() {
                await waitForReadiness()
                return
            }
        }

        appState.connectionStatus = .disconnected
        appState.serviceErrorMessage = "Agent Service is unavailable."
    }

    private func waitForReadiness() async {
        appState.connectionStatus = .starting
        for _ in 0..<20 {
            if await probeHealth() {
                consecutiveFailures = 0
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        appState.connectionStatus = .error
        appState.serviceErrorMessage = "Agent Service started but did not become ready."
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

    private func launchAgentService() -> Bool {
        guard let pythonURL = locatePython() else {
            Self.logger.error("Python not found for Agent Service")
            return false
        }

        let projectRoot = locateProjectRoot()
        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = [
            "-m", "uvicorn",
            "agent_service.app:app",
            "--host", "127.0.0.1",
            "--port", "8782",
            "--log-level", "warning"
        ]
        if let projectRoot {
            proc.currentDirectoryURL = projectRoot
        }

        var env = ProcessInfo.processInfo.environment
        env["PIKI_APP_MANAGED_SERVICE"] = "1"
        proc.environment = env

        let logURL = pikiLogDirectory().appendingPathComponent("agent-service.log")
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            _ = try? logHandle.seekToEnd()
            proc.standardError = logHandle
            proc.standardOutput = logHandle
        } else {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            if let logHandle = try? FileHandle(forWritingTo: logURL) {
                proc.standardError = logHandle
                proc.standardOutput = logHandle
            }
        }

        do {
            try proc.run()
            self.process = proc
            launchedProcess = true
            Self.logger.info("Agent Service launched pid=\(proc.processIdentifier)")
            return true
        } catch {
            Self.logger.error("Failed to launch Agent Service: \(error.localizedDescription)")
            appState.serviceErrorMessage = "Failed to start Agent Service: \(error.localizedDescription)"
            return false
        }
    }

    private func stopProcess() {
        guard let process, process.isRunning else {
            self.process = nil
            launchedProcess = false
            return
        }
        process.terminate()
        self.process = nil
        launchedProcess = false
    }

    private func locatePython() -> URL? {
        let candidates = [
            pikiHome().appendingPathComponent("venv/bin/python"),
            locateProjectRoot()?.appendingPathComponent(".venv/bin/python"),
            URL(fileURLWithPath: "/opt/anaconda3/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ].compactMap { $0 }

        for url in candidates {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func locateProjectRoot() -> URL? {
        let knownPath = URL(fileURLWithPath: "/Users/a99/localDocuments/codeBase/ideaWorkplace/piki")
        if FileManager.default.fileExists(atPath: knownPath.appendingPathComponent("pyproject.toml").path) {
            return knownPath
        }
        return nil
    }

    private func pikiHome() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".piki", isDirectory: true)
    }

    private func pikiLogDirectory() -> URL {
        let dir = pikiHome()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
