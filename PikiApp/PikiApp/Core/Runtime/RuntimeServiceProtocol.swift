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

    func runLint(vaultPath: String) async throws -> LintResultDTO
    func fixLint(vaultPath: String, issueIds: [String]?) async throws
}
