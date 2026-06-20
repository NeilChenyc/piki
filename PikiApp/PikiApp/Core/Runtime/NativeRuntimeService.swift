import Foundation

@Observable
@MainActor
final class NativeRuntimeService: RuntimeServiceProtocol {
    private let connection: RuntimeHostConnection

    init(hostExecutableURL: URL) {
        self.connection = RuntimeHostConnection(hostExecutableURL: hostExecutableURL)
    }

    static func makeDefault() -> NativeRuntimeService? {
        guard let hostURL = RuntimeHostConnection.locateHostExecutable() else {
            return nil
        }
        return NativeRuntimeService(hostExecutableURL: hostURL)
    }

    static func fallbackUnavailableService() -> NativeRuntimeService {
        NativeRuntimeService(hostExecutableURL: URL(fileURLWithPath: "/usr/bin/false"))
    }

    func health() async throws -> ServiceHealth {
        try await decode(connection.call(method: "health"))
    }

    func getRuntimeConfig() async throws -> RuntimeConfigDTO {
        try await decode(connection.call(method: "get_runtime_config"))
    }

    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        try await decode(connection.call(method: "update_runtime_config", params: try JSONValue(encoding: request)))
    }

    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse {
        try await decode(connection.call(method: "smoke_test_runtime"))
    }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        try await decode(connection.call(method: "create_task", params: try JSONValue(encoding: request)))
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        connection.taskEvents(taskId: taskId)
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        try await decode(connection.call(method: "get_task", params: .object(["task_id": .string(taskId)])))
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        try await decode(connection.call(
            method: "submit_task_input",
            params: .object(["task_id": .string(taskId), "message": .string(message)])
        ))
    }

    func cancelTask(taskId: String) async throws -> TaskRecordDTO {
        try await decode(connection.call(method: "cancel_task", params: .object(["task_id": .string(taskId)])))
    }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        let fileData = try readAttachmentData(from: fileURL)
        let params: JSONValue = .object([
            "filename": .string(fileURL.lastPathComponent),
            "original_path": .string(fileURL.path(percentEncoded: false)),
            "mime_type": .string(mimeType(for: fileURL)),
            "content_base64": .string(fileData.base64EncodedString())
        ])
        return try await decode(connection.call(method: "upload_file", params: params))
    }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] {
        try await decode(connection.call(method: "recent_journal", params: .object([
            "limit": .number(Double(limit)),
            "vault_path": vaultPath.map(JSONValue.string) ?? .null
        ])))
    }

    func rollback(entryId: String) async throws {
        _ = try await connection.call(method: "rollback", params: .object(["entry_id": .string(entryId)]))
    }

    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] {
        try await decode(connection.call(method: "list_ingest_queue", params: .object([
            "status": status.map(JSONValue.string) ?? .null
        ])))
    }

    func enqueueIngest(vaultPath: String, paths: [String]) async throws {
        _ = try await connection.call(method: "enqueue_ingest", params: .object([
            "vault_path": .string(vaultPath),
            "paths": .array(paths.map(JSONValue.string))
        ]))
    }

    func processIngestQueue(vaultPath: String?) async throws {
        _ = try await connection.call(method: "process_ingest_queue", params: .object([
            "vault_path": vaultPath.map(JSONValue.string) ?? .null
        ]))
    }

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        try await decode(connection.call(method: "run_lint", params: .object(["vault_path": .string(vaultPath)])))
    }

    func fixLint(vaultPath: String, issueIds: [String]?) async throws {
        _ = try await connection.call(method: "fix_lint", params: .object([
            "vault_path": .string(vaultPath),
            "issue_ids": .array((issueIds ?? []).map(JSONValue.string))
        ]))
    }

    func stop() {
        connection.stop()
    }

    private func decode<T: Decodable>(_ data: Data) async throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private func readAttachmentData(from fileURL: URL) throws -> Data {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: fileURL)
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "md", "markdown": return "text/markdown"
        case "txt": return "text/plain"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default: return "application/octet-stream"
        }
    }
}
