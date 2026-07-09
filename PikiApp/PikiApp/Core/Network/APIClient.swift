import Foundation

@Observable
@MainActor
final class APIClient {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
    }

    // MARK: - Health

    func health() async throws -> ServiceHealth {
        let url = baseURL.appending(path: "health")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ServiceHealth.self, from: data)
    }

    func checkHealth() async throws -> Bool {
        try await health().ok
    }

    // MARK: - Runtime Configuration

    func getRuntimeConfig() async throws -> RuntimeConfigDTO {
        let url = baseURL.appending(path: "runtime/config")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RuntimeConfigDTO.self, from: data)
    }

    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        let url = baseURL.appending(path: "runtime/config")
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RuntimeConfigDTO.self, from: data)
    }

    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse {
        let url = baseURL.appending(path: "runtime/smoke-test")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RuntimeSmokeTestResponse.self, from: data)
    }

    // MARK: - Tasks

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        let url = baseURL.appending(path: "tasks")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TaskCreateResponse.self, from: data)
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        let url = baseURL.appending(path: "tasks/\(taskId)/events")
        return SSEClient.stream(url: url)
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        let url = baseURL.appending(path: "tasks/\(taskId)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TaskRecordDTO.self, from: data)
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        let url = baseURL.appending(path: "tasks/\(taskId)/input")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(TaskInputRequest(message: message))
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TaskRecordDTO.self, from: data)
    }

    func cancelTask(taskId: String) async throws -> TaskRecordDTO {
        let url = baseURL.appending(path: "tasks/\(taskId)/cancel")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TaskRecordDTO.self, from: data)
    }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        let url = baseURL.appending(path: "uploads")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try readAttachmentData(from: fileURL)
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"original_path\"\r\n\r\n".data(using: .utf8)!)
        body.append(fileURL.path(percentEncoded: false).data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: req, from: body)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(BufferedUploadResponse.self, from: data)
    }

    // MARK: - Journal

    func recentJournal(limit: Int = 10, vaultPath: String? = nil) async throws -> [JournalEntry] {
        var url = baseURL.appending(path: "journal/recent")
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let vaultPath {
            queryItems.append(URLQueryItem(name: "vault_path", value: vaultPath))
        }
        url.append(queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        let journalResponse = try JSONDecoder().decode(JournalResponse.self, from: data)
        return journalResponse.entries
    }

    // MARK: - Inspirations

    func listInspirations(vaultPath: String, query: String? = nil) async throws -> [InspirationDTO] {
        var url = baseURL.appending(path: "inspirations")
        var queryItems = [URLQueryItem(name: "vault_path", value: vaultPath)]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        url.append(queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(InspirationListResponse.self, from: data).items
    }

    func createInspiration(_ request: InspirationCreateRequest) async throws -> InspirationDTO {
        let url = baseURL.appending(path: "inspirations")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(InspirationDTO.self, from: data)
    }

    func updateInspiration(id: String, request: InspirationUpdateRequest) async throws -> InspirationDTO {
        let url = baseURL.appending(path: "inspirations/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(InspirationDTO.self, from: data)
    }

    func compileInspirations(vaultPath: String) async throws -> InspirationCompileResponse {
        let url = baseURL.appending(path: "inspirations/compile")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(InspirationCompileRequest(vaultPath: vaultPath))
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(InspirationCompileResponse.self, from: data)
    }

    func deleteInspiration(id: String, vaultPath: String) async throws {
        var url = baseURL.appending(path: "inspirations/\(id)")
        url.append(queryItems: [URLQueryItem(name: "vault_path", value: vaultPath)])
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: - Lint

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        let response = try await createTask(
            TaskCreateRequest(
                vaultPath: vaultPath,
                userInput: "Run vault lint.",
                actionContext: ["action": "run_lint"]
            )
        )
        let task = try await getTask(taskId: response.taskId)
        if task.status == "failed" {
            throw APIError.serverMessage(task.summary ?? "Lint agent task failed.")
        }
        guard let lintResult = task.output?.lintResult else {
            throw APIError.serverMessage("Lint agent task did not return a lint result.")
        }
        return lintResult
    }

    func fixLint(vaultPath: String, issueIds: [String]? = nil) async throws {
        let url = baseURL.appending(path: "lint/fix")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["vault_path": vaultPath]
        if let issueIds { body["issue_ids"] = issueIds }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                if let userFacingError = response.error {
                    throw APIError.userFacing(userFacingError)
                }
                throw APIError.serverMessage(response.detail ?? "Server error: \(http.statusCode)")
            }
            throw APIError.serverMessage("Server error: \(http.statusCode)")
        }
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
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}
