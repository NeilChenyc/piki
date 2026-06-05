import Foundation

enum SSEClient {
    static func stream(url: URL) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          http.statusCode == 200 else {
                        continuation.finish(throwing: APIError.connectionFailed)
                        return
                    }

                    var dataBuffer = ""

                    for try await line in bytes.lines {
                        if line.hasPrefix(":") {
                            continue
                        } else if line.hasPrefix("event:") {
                            continue
                        } else if line.hasPrefix("data:") {
                            dataBuffer += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else if line.isEmpty {
                            if !dataBuffer.isEmpty {
                                if let data = dataBuffer.data(using: .utf8),
                                   let event = try? JSONDecoder().decode(TaskEvent.self, from: data) {
                                    continuation.yield(event)
                                }
                            }
                            dataBuffer = ""
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum APIError: Error, LocalizedError {
    case connectionFailed
    case invalidResponse
    case serverError(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Failed to connect to Agent Service"
        case .invalidResponse: "Invalid response from server"
        case .serverError(let code): "Server error: \(code)"
        case .serverMessage(let message): message
        }
    }
}
