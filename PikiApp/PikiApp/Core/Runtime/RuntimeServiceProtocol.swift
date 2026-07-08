import Foundation

@MainActor
protocol RuntimeServiceProtocol: AnyObject {
    func health() async throws -> ServiceHealth
    func getRuntimeConfig() async throws -> RuntimeConfigDTO
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error>
    func getTask(taskId: String) async throws -> TaskRecordDTO
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO
    func cancelTask(taskId: String) async throws -> TaskRecordDTO
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry]
    func rollback(entryId: String) async throws

    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO]
    func enqueueIngest(vaultPath: String, paths: [String]) async throws
    func processIngestQueue(vaultPath: String?) async throws

    func listInspirations(vaultPath: String, query: String?) async throws -> [InspirationDTO]
    func createInspiration(_ request: InspirationCreateRequest) async throws -> InspirationDTO
    func updateInspiration(id: String, request: InspirationUpdateRequest) async throws -> InspirationDTO
    func deleteInspiration(id: String, vaultPath: String) async throws
    func compileInspirations(vaultPath: String) async throws -> InspirationCompileResponse

    func runLint(vaultPath: String) async throws -> LintResultDTO
    func fixLint(vaultPath: String, issueIds: [String]?) async throws
}

extension RuntimeServiceProtocol {
    func listInspirations(vaultPath: String, query: String?) async throws -> [InspirationDTO] {
        throw RuntimeError.runtimeHostUnavailable
    }

    func createInspiration(_ request: InspirationCreateRequest) async throws -> InspirationDTO {
        throw RuntimeError.runtimeHostUnavailable
    }

    func updateInspiration(id: String, request: InspirationUpdateRequest) async throws -> InspirationDTO {
        throw RuntimeError.runtimeHostUnavailable
    }

    func deleteInspiration(id: String, vaultPath: String) async throws {
        throw RuntimeError.runtimeHostUnavailable
    }

    func compileInspirations(vaultPath: String) async throws -> InspirationCompileResponse {
        throw RuntimeError.runtimeHostUnavailable
    }
}
