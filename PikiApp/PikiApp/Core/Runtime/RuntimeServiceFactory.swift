import Foundation

@MainActor
enum RuntimeServiceFactory {
    static func makeDefault() -> any RuntimeServiceProtocol {
        if let native = NativeRuntimeService.makeDefault() {
            return native
        }
        return UnavailableRuntimeService()
    }
}

@MainActor
final class UnavailableRuntimeService: RuntimeServiceProtocol {
    private func fail<T>() async throws -> T {
        throw RuntimeError.runtimeHostUnavailable
    }

    func health() async throws -> ServiceHealth { try await fail() }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { try await fail() }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { try await fail() }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { try await fail() }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { try await fail() }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: RuntimeError.runtimeHostUnavailable)
        }
    }
    func getTask(taskId: String) async throws -> TaskRecordDTO { try await fail() }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { try await fail() }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { try await fail() }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { try await fail() }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { try await fail() }
    func rollback(entryId: String) async throws { let _: Void = try await fail() }
    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] { try await fail() }
    func enqueueIngest(vaultPath: String, paths: [String]) async throws { let _: Void = try await fail() }
    func processIngestQueue(vaultPath: String?) async throws { let _: Void = try await fail() }
    func runLint(vaultPath: String) async throws -> LintResultDTO { try await fail() }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws { let _: Void = try await fail() }
}

enum RuntimeError: LocalizedError {
    case runtimeHostUnavailable

    var errorDescription: String? {
        "Piki runtime host is unavailable."
    }
}
