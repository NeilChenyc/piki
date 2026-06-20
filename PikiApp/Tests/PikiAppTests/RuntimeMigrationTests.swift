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

    func rollback(entryId: String) async throws {
        throw StubRuntimeError.unimplemented
    }

    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] {
        throw StubRuntimeError.unimplemented
    }

    func enqueueIngest(vaultPath: String, paths: [String]) async throws {
        throw StubRuntimeError.unimplemented
    }

    func processIngestQueue(vaultPath: String?) async throws {
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
