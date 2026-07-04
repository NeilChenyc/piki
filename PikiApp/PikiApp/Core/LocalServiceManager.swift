import Foundation
import os

struct RuntimeBundleConfiguration: Equatable {
    let pythonURL: URL
    let sitePackagesURL: URL?
}

private struct RuntimePathsManifest: Decodable {
    let python: String
    let sitePackages: String?

    private enum CodingKeys: String, CodingKey {
        case python
        case sitePackages = "site_packages"
    }
}

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

        if launchedProcess {
            stopProcess()
        } else {
            terminateConflictingServices()
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
        let projectRoot = locateProjectRoot()
        let pikiHome = pikiHome()
        Self.prepareManagedRuntimeEnvironment(at: pikiHome)
        let bundleRuntime = Self.runtimeBundleConfiguration(resourcesURL: Bundle.main.resourceURL)
        guard let pythonURL = locatePython(
            resourcesURL: Bundle.main.resourceURL,
            projectRoot: projectRoot,
            pikiHome: pikiHome
        ) else {
            Self.logger.error("Python not found for Agent Service")
            return false
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = [
            "-m", "uvicorn",
            "agent_service.app:app",
            "--host", "127.0.0.1",
            "--port", "8782",
            "--log-level", "warning"
        ]
        if pythonURL == bundleRuntime?.pythonURL {
            proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        } else if let projectRoot {
            proc.currentDirectoryURL = projectRoot
        } else {
            proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        proc.environment = Self.managedServiceEnvironment(
            baseEnvironment: ProcessInfo.processInfo.environment,
            pikiHome: pikiHome,
            pythonURL: pythonURL,
            bundleRuntime: bundleRuntime
        )

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
            restartCount = 0
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
        Self.terminateProcess(process)
        self.process = nil
        launchedProcess = false
    }

    private func terminateConflictingServices() {
        let pids = Self.listeningProcessIdentifiers(onPort: 8782)
        guard pids.isEmpty == false else {
            return
        }

        Self.logger.warning("Terminating existing Agent Service listeners on port 8782: \(pids)")
        for pid in pids {
            Self.terminateProcess(pid: pid)
        }
    }

    private func locatePython(resourcesURL: URL?, projectRoot: URL?, pikiHome: URL) -> URL? {
        let candidates = Self.pythonCandidates(
            resourcesURL: resourcesURL,
            projectRoot: projectRoot,
            pikiHome: pikiHome
        )

        for url in candidates {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func runtimeBundleConfiguration(
        resourcesURL: URL?,
        fileManager: FileManager = .default
    ) -> RuntimeBundleConfiguration? {
        guard let resourcesURL else {
            return nil
        }
        let metadataURL = resourcesURL.appendingPathComponent("runtime-paths.json")
        guard
            let data = try? Data(contentsOf: metadataURL),
            let manifest = try? JSONDecoder().decode(RuntimePathsManifest.self, from: data)
        else {
            return nil
        }

        let pythonURL = resourcesURL.appendingPathComponent(manifest.python)
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            return nil
        }

        var sitePackagesURL: URL? = nil
        if let rawSitePackagesPath = manifest.sitePackages?.trimmingCharacters(in: .whitespacesAndNewlines),
           rawSitePackagesPath.isEmpty == false {
            let candidate = resourcesURL.appendingPathComponent(rawSitePackagesPath)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                sitePackagesURL = candidate
            }
        }

        return RuntimeBundleConfiguration(
            pythonURL: pythonURL,
            sitePackagesURL: sitePackagesURL
        )
    }

    static func pythonCandidates(
        resourcesURL: URL?,
        projectRoot: URL?,
        pikiHome: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        var candidates: [URL] = []
        if let bundledRuntime = runtimeBundleConfiguration(resourcesURL: resourcesURL, fileManager: fileManager) {
            candidates.append(bundledRuntime.pythonURL)
        }
        candidates.append(contentsOf: [
            pikiHome.appendingPathComponent("venv/bin/python"),
            projectRoot?.appendingPathComponent(".venv/bin/python"),
            URL(fileURLWithPath: "/opt/anaconda3/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ].compactMap { $0 })

        var uniqueCandidates: [URL] = []
        var seenPaths = Set<String>()
        for url in candidates {
            let standardizedPath = url.standardizedFileURL.path
            if seenPaths.insert(standardizedPath).inserted {
                uniqueCandidates.append(url)
            }
        }
        return uniqueCandidates
    }

    static func mergedPythonPath(existingPythonPath: String?, sitePackagesURL: URL?) -> String? {
        let existingEntries = (existingPythonPath ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { $0.isEmpty == false }
        var entries: [String] = []
        if let sitePackagesURL {
            entries.append(sitePackagesURL.path)
        }
        entries.append(contentsOf: existingEntries)
        if entries.isEmpty {
            return nil
        }

        var uniqueEntries: [String] = []
        var seen = Set<String>()
        for entry in entries {
            if seen.insert(entry).inserted {
                uniqueEntries.append(entry)
            }
        }
        return uniqueEntries.joined(separator: ":")
    }

    static func managedServiceEnvironment(
        baseEnvironment: [String: String],
        pikiHome: URL,
        pythonURL: URL,
        bundleRuntime: RuntimeBundleConfiguration?
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PIKI_APP_MANAGED_SERVICE"] = "1"
        environment["PIKI_ENABLE_AGENT_RUNTIME"] = "1"
        environment["CLAUDE_CONFIG_DIR"] = pikiHome.appendingPathComponent("claude-runtime", isDirectory: true).path
        environment["PIKI_TASK_STAGING_ROOT"] = pikiHome.appendingPathComponent("task-staging", isDirectory: true).path

        if pythonURL == bundleRuntime?.pythonURL {
            environment["PIKI_APP_RUNTIME_SOURCE"] = "bundle"
            if let pythonPath = Self.mergedPythonPath(
                existingPythonPath: environment["PYTHONPATH"],
                sitePackagesURL: bundleRuntime?.sitePackagesURL
            ) {
                environment["PYTHONPATH"] = pythonPath
            }
        }

        return environment
    }

    static func listeningProcessIdentifiers(onPort port: Int) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "lsof -nP -iTCP:\(port) -sTCP:LISTEN -t 2>/dev/null"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }
        return listeningProcessIdentifiers(from: output)
    }

    static func listeningProcessIdentifiers(from output: String) -> [Int32] {
        var pids = Set<Int32>()
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(trimmed) else {
                continue
            }
            pids.insert(pid)
        }
        return pids.sorted()
    }

    static func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
    }

    static func terminateProcess(_ process: Process, gracePeriod: TimeInterval = 2.0) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    private func locateProjectRoot() -> URL? {
        Self.developmentProjectRoot()
    }

    private func pikiHome() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".piki", isDirectory: true)
    }

    private func pikiLogDirectory() -> URL {
        let dir = pikiHome()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func developmentProjectRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        fileManager: FileManager = .default,
        sourceFileURL: URL = URL(fileURLWithPath: #filePath)
    ) -> URL? {
        if let envPath = environment["PIKI_REPO_ROOT"], envPath.isEmpty == false {
            let candidate = URL(fileURLWithPath: envPath, isDirectory: true)
            if containsPyproject(at: candidate, fileManager: fileManager) {
                return candidate
            }
        }

        let sourceStart = sourceFileURL.hasDirectoryPath ? sourceFileURL : sourceFileURL.deletingLastPathComponent()
        if let root = repositoryRoot(containing: "pyproject.toml", startingAt: sourceStart, fileManager: fileManager) {
            return root
        }

        if let currentDirectoryURL,
           let root = repositoryRoot(containing: "pyproject.toml", startingAt: currentDirectoryURL, fileManager: fileManager) {
            return root
        }

        return nil
    }

    static func prepareManagedRuntimeEnvironment(
        at pikiHome: URL,
        fileManager: FileManager = .default
    ) {
        let directories = [
            pikiHome,
            pikiHome.appendingPathComponent("claude-runtime", isDirectory: true),
            pikiHome.appendingPathComponent("task-staging", isDirectory: true),
        ]

        for directory in directories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func repositoryRoot(
        containing markerFile: String,
        startingAt startURL: URL,
        fileManager: FileManager
    ) -> URL? {
        var candidate = startURL.standardizedFileURL
        if candidate.hasDirectoryPath == false {
            candidate = candidate.deletingLastPathComponent()
        }

        while true {
            if containsPyproject(at: candidate, fileManager: fileManager, markerFile: markerFile) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent == candidate {
                return nil
            }
            candidate = parent
        }
    }

    private static func containsPyproject(
        at directory: URL,
        fileManager: FileManager,
        markerFile: String = "pyproject.toml"
    ) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent(markerFile).path)
    }
}
