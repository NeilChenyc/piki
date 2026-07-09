import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Runtime migration")
struct RuntimeMigrationTests {
    @Test
    func localServiceManagerKeepsInjectedRuntimeService() async throws {
        let runtime = StubRuntimeService(healthResult: ServiceHealth(
            ok: true,
            runnerAvailable: true,
            runnerDetail: "stub runtime",
            provider: "native",
            anthropicAPIKeyConfigured: false,
            anthropicBaseURL: nil,
            agentModel: nil,
            agentRuntimeEnabled: false,
            agentRuntimeConfigured: false,
            claudeConfigDir: nil
        ))
        let appState = AppState(runtimeService: runtime)
        let manager = LocalServiceManager(appState: appState)

        await manager.start()
        defer { manager.stop() }

        #expect(appState.runtimeService === runtime)
        #expect(runtime.healthCallCount == 1)
        #expect(appState.connectionStatus == .connected)
    }

    @Test
    func runtimeBundleConfigurationParsesBundledPythonAndSitePackages() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourcesURL = tempRoot.appendingPathComponent("Resources", isDirectory: true)
        let pythonURL = resourcesURL.appendingPathComponent("PikiRuntime/Python/bin/python3")
        let sitePackagesURL = resourcesURL.appendingPathComponent("PikiRuntime/site-packages", isDirectory: true)

        try FileManager.default.createDirectory(at: pythonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sitePackagesURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pythonURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonURL.path
        )
        try """
        {"python":"PikiRuntime/Python/bin/python3","site_packages":"PikiRuntime/site-packages","arch":"aarch64"}
        """.write(to: resourcesURL.appendingPathComponent("runtime-paths.json"), atomically: true, encoding: .utf8)

        let configuration = LocalServiceManager.runtimeBundleConfiguration(resourcesURL: resourcesURL)

        #expect(configuration?.pythonURL == pythonURL)
        #expect(configuration?.sitePackagesURL == sitePackagesURL)
    }

    @Test
    func pythonCandidatesPreferBundledRuntimeAheadOfFallbacks() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourcesURL = tempRoot.appendingPathComponent("Resources", isDirectory: true)
        let pikiHome = tempRoot.appendingPathComponent(".piki-home", isDirectory: true)
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let bundledPythonURL = resourcesURL.appendingPathComponent("PikiRuntime/Python/bin/python3")

        try FileManager.default.createDirectory(at: bundledPythonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bundledPythonURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledPythonURL.path
        )
        try """
        {"python":"PikiRuntime/Python/bin/python3","site_packages":"PikiRuntime/site-packages","arch":"aarch64"}
        """.write(to: resourcesURL.appendingPathComponent("runtime-paths.json"), atomically: true, encoding: .utf8)

        let candidates = LocalServiceManager.pythonCandidates(
            resourcesURL: resourcesURL,
            projectRoot: projectRoot,
            pikiHome: pikiHome
        )

        #expect(candidates.first == bundledPythonURL)
    }

    @Test
    func mergedPythonPathPrependsBundledSitePackagesOnce() {
        let sitePackagesURL = URL(fileURLWithPath: "/tmp/PikiRuntime/site-packages", isDirectory: true)

        let merged = LocalServiceManager.mergedPythonPath(
            existingPythonPath: "/usr/lib/python:/tmp/PikiRuntime/site-packages",
            sitePackagesURL: sitePackagesURL
        )

        #expect(merged == "/tmp/PikiRuntime/site-packages:/usr/lib/python")
    }

    @Test
    func listeningProcessIdentifiersParsesDistinctNumericPIDs() {
        let pids = LocalServiceManager.listeningProcessIdentifiers(
            from: "74716\n 67282 \ninvalid\n74716\n"
        )

        #expect(pids == [67282, 74716])
    }

    @Test
    func listeningProcessIdentifiersIgnoresBlankOutput() {
        let pids = LocalServiceManager.listeningProcessIdentifiers(from: "\n \n")

        #expect(pids.isEmpty)
    }
}

@MainActor
private final class StubRuntimeService: RuntimeServiceProtocol {
    private let healthResult: ServiceHealth
    private(set) var healthCallCount = 0

    init(healthResult: ServiceHealth) {
        self.healthResult = healthResult
    }

    func health() async throws -> ServiceHealth {
        healthCallCount += 1
        return healthResult
    }

    func getRuntimeConfig() async throws -> RuntimeConfigDTO {
        throw StubRuntimeError.unimplemented
    }

    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        throw StubRuntimeError.unimplemented
    }

    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse {
        throw StubRuntimeError.unimplemented
    }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        throw StubRuntimeError.unimplemented
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        throw StubRuntimeError.unimplemented
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        throw StubRuntimeError.unimplemented
    }

    func cancelTask(taskId: String) async throws -> TaskRecordDTO {
        throw StubRuntimeError.unimplemented
    }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        throw StubRuntimeError.unimplemented
    }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] {
        throw StubRuntimeError.unimplemented
    }

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        throw StubRuntimeError.unimplemented
    }

    func fixLint(vaultPath: String, issueIds: [String]?) async throws {
        throw StubRuntimeError.unimplemented
    }
}

private enum StubRuntimeError: Error {
    case unimplemented
}
