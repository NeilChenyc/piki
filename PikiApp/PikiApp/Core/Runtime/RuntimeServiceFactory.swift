import Foundation

@MainActor
enum RuntimeServiceFactory {
    static func makeDefault() -> any RuntimeServiceProtocol {
        DeferredNativeRuntimeService()
    }
}

@MainActor
final class DeferredNativeRuntimeService: RuntimeServiceProtocol {
    private var cachedService: NativeRuntimeService?

    private func resolveService() throws -> NativeRuntimeService {
        if let cachedService {
            return cachedService
        }

        guard let native = NativeRuntimeService.makeDefault() else {
            throw RuntimeError.runtimeHostUnavailable
        }
        cachedService = native
        return native
    }

    private func call<T>(_ work: (NativeRuntimeService) async throws -> T) async throws -> T {
        let service = try resolveService()
        do {
            return try await work(service)
        } catch let error as RuntimeHostConnection.ConnectionError where error.shouldRetry {
            service.stop()
            cachedService = nil
            let retryService = try resolveService()
            return try await work(retryService)
        }
    }

    func health() async throws -> ServiceHealth {
        try await call { try await $0.health() }
    }

    func getRuntimeConfig() async throws -> RuntimeConfigDTO {
        try await call { try await $0.getRuntimeConfig() }
    }

    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        try await call { try await $0.updateRuntimeConfig(request) }
    }

    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse {
        try await call { try await $0.smokeTestRuntime() }
    }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        try await call { try await $0.createTask(request) }
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        guard let service = try? resolveService() else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RuntimeError.runtimeHostUnavailable)
            }
        }
        return service.taskEvents(taskId: taskId)
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        try await call { try await $0.getTask(taskId: taskId) }
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        try await call { try await $0.submitTaskInput(taskId: taskId, message: message) }
    }

    func cancelTask(taskId: String) async throws -> TaskRecordDTO {
        try await call { try await $0.cancelTask(taskId: taskId) }
    }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        try await call { try await $0.uploadFile(fileURL) }
    }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] {
        try await call { try await $0.recentJournal(limit: limit, vaultPath: vaultPath) }
    }

    func rollback(entryId: String) async throws {
        try await call { service in
            try await service.rollback(entryId: entryId)
        }
    }

    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] {
        try await call { try await $0.listIngestQueue(status: status) }
    }

    func enqueueIngest(vaultPath: String, paths: [String]) async throws {
        try await call { service in
            try await service.enqueueIngest(vaultPath: vaultPath, paths: paths)
        }
    }

    func processIngestQueue(vaultPath: String?) async throws {
        try await call { service in
            try await service.processIngestQueue(vaultPath: vaultPath)
        }
    }

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        try await call { try await $0.runLint(vaultPath: vaultPath) }
    }

    func fixLint(vaultPath: String, issueIds: [String]?) async throws {
        try await call { service in
            try await service.fixLint(vaultPath: vaultPath, issueIds: issueIds)
        }
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
