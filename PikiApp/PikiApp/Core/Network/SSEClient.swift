import Foundation
import OSLog

enum SSEClient {
    private static let logger = Logger(subsystem: "com.piki.app", category: "SSEClient")

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
                    func flushBuffer() {
                        guard !dataBuffer.isEmpty else { return }
                        defer { dataBuffer = "" }
                        guard let data = dataBuffer.data(using: .utf8) else { return }
                        do {
                            let event = try JSONDecoder().decode(TaskEvent.self, from: data)
                            #if DEBUG
                            logger.log("SSE decoded event: \(event.type, privacy: .public)")
                            #endif
                            continuation.yield(event)
                        } catch {
                            #if DEBUG
                            logger.error("SSE decode failed: \(error.localizedDescription, privacy: .public)")
                            logger.error("SSE payload: \(dataBuffer, privacy: .public)")
                            #endif
                        }
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix(":") {
                            flushBuffer()
                            #if DEBUG
                            logger.log("SSE heartbeat from \(url.absoluteString, privacy: .public)")
                            #endif
                            continue
                        } else if line.hasPrefix("event:") {
                            flushBuffer()
                            #if DEBUG
                            logger.log("SSE event line: \(line, privacy: .public)")
                            #endif
                            continue
                        } else if line.hasPrefix("data:") {
                            let payloadLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if dataBuffer.isEmpty {
                                dataBuffer = payloadLine
                            } else {
                                dataBuffer += "\n" + payloadLine
                            }
                        } else if line.isEmpty {
                            flushBuffer()
                        }
                    }
                    flushBuffer()
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
