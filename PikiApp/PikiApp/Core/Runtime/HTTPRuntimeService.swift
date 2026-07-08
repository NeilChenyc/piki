import Foundation

@Observable
@MainActor
final class HTTPRuntimeService: RuntimeServiceProtocol {
    private let client = APIClient()

    var baseURL: URL {
        didSet { client.baseURL = baseURL }
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.client.baseURL = baseURL
    }

    func health() async throws -> ServiceHealth { try await client.health() }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { try await client.getRuntimeConfig() }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        try await client.updateRuntimeConfig(request)
    }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { try await client.smokeTestRuntime() }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { try await client.createTask(request) }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { client.taskEvents(taskId: taskId) }
    func getTask(taskId: String) async throws -> TaskRecordDTO { try await client.getTask(taskId: taskId) }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        try await client.submitTaskInput(taskId: taskId, message: message)
    }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { try await client.cancelTask(taskId: taskId) }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { try await client.uploadFile(fileURL) }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] {
        try await client.recentJournal(limit: limit, vaultPath: vaultPath)
    }
    func rollback(entryId: String) async throws { try await client.rollback(entryId: entryId) }

    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] {
        try await client.listIngestQueue(status: status)
    }
    func enqueueIngest(vaultPath: String, paths: [String]) async throws {
        try await client.enqueueIngest(vaultPath: vaultPath, paths: paths)
    }
    func processIngestQueue(vaultPath: String?) async throws {
        try await client.processIngestQueue(vaultPath: vaultPath)
    }

    func listInspirations(vaultPath: String, query: String?) async throws -> [InspirationDTO] {
        try await client.listInspirations(vaultPath: vaultPath, query: query)
    }
    func createInspiration(_ request: InspirationCreateRequest) async throws -> InspirationDTO {
        try await client.createInspiration(request)
    }
    func updateInspiration(id: String, request: InspirationUpdateRequest) async throws -> InspirationDTO {
        try await client.updateInspiration(id: id, request: request)
    }
    func deleteInspiration(id: String, vaultPath: String) async throws {
        try await client.deleteInspiration(id: id, vaultPath: vaultPath)
    }
    func compileInspirations(vaultPath: String) async throws -> InspirationCompileResponse {
        try await client.compileInspirations(vaultPath: vaultPath)
    }

    func runLint(vaultPath: String) async throws -> LintResultDTO { try await client.runLint(vaultPath: vaultPath) }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {
        try await client.fixLint(vaultPath: vaultPath, issueIds: issueIds)
    }
}
