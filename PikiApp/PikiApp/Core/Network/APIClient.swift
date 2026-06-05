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

    func rollback(entryId: String) async throws {
        let url = baseURL.appending(path: "journal/\(entryId)/rollback")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: - Ingest Queue

    func listIngestQueue(status: String? = nil) async throws -> [IngestQueueItemDTO] {
        var url = baseURL.appending(path: "ingest-queue")
        if let status {
            url.append(queryItems: [URLQueryItem(name: "status", value: status)])
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(IngestQueueResponse.self, from: data).items
    }

    func enqueueIngest(vaultPath: String, paths: [String]) async throws {
        let url = baseURL.appending(path: "ingest-queue/enqueue")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["vault_path": vaultPath, "selected_paths": paths] as [String: Any]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    func processIngestQueue(vaultPath: String? = nil) async throws {
        let url = baseURL.appending(path: "ingest-queue/process")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let vaultPath {
            req.httpBody = try JSONSerialization.data(withJSONObject: ["vault_path": vaultPath])
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: - Lint

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        let url = baseURL.appending(path: "lint")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["vault_path": vaultPath])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LintResultDTO.self, from: data)
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
            let detail = try? JSONDecoder().decode(APIErrorResponse.self, from: data).detail
            throw APIError.serverMessage(detail ?? "Server error: \(http.statusCode)")
        }
    }
}
