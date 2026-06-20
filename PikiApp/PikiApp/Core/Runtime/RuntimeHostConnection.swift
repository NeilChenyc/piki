import Foundation

final class RuntimeHostConnection: @unchecked Sendable {
    private struct HostResponse: Decodable {
        let kind: String
        let id: String
        let result: JSONValue?
        let error: String?
    }

    private struct HostRequest: Encodable {
        let id: String
        let method: String
        let params: JSONValue
    }

    enum ConnectionError: Error, LocalizedError {
        case hostNotFound
        case hostNotRunning
        case invalidResponse
        case remoteError(String)

        var errorDescription: String? {
            switch self {
            case .hostNotFound:
                return "PikiRuntimeHost was not found."
            case .hostNotRunning:
                return "PikiRuntimeHost is not running."
            case .invalidResponse:
                return "Invalid response from runtime host."
            case .remoteError(let message):
                return message
            }
        }
    }

    private let hostExecutableURL: URL
    private let stateQueue = DispatchQueue(label: "com.piki.runtime-host-connection")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<Data, Error>] = [:]

    init(hostExecutableURL: URL) {
        self.hostExecutableURL = hostExecutableURL
    }

    static func locateHostExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PikiRuntimeHost"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PikiRuntimeHost"),
        ].compactMap { $0 }
        for url in candidates where fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    func call(method: String, params: JSONValue = .object([:])) async throws -> Data {
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync {
                pendingResponses[id] = continuation
            }
            do {
                try ensureStarted()
                try writeRequest(id: id, method: method, params: params)
            } catch {
                stateQueue.sync {
                    pendingResponses[id] = nil
                }
                continuation.resume(throwing: error)
            }
        }
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TaskEvent.self, throwing: Error.self)
        let pollTask = Task { [weak self] in
            guard let self else { return }
            var seenIDs = Set<String>()
            while !Task.isCancelled {
                do {
                    let data = try await self.call(
                        method: "task_events",
                        params: .object(["task_id": .string(taskId)])
                    )
                    let events = try JSONDecoder().decode([TaskEvent].self, from: data)
                    for event in events where seenIDs.insert(event.id).inserted {
                        continuation.yield(event)
                    }
                    try await Task.sleep(for: .milliseconds(200))
                } catch is CancellationError {
                    break
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pollTask.cancel() }
        return stream
    }

    func stop() {
        let responses: [CheckedContinuation<Data, Error>] = stateQueue.sync {
            stdoutTask?.cancel()
            stdoutTask = nil
            if process?.isRunning == true {
                process?.terminate()
            }
            process = nil
            stdinHandle = nil
            let responses = Array(pendingResponses.values)
            pendingResponses.removeAll()
            return responses
        }
        responses.forEach { $0.resume(throwing: ConnectionError.hostNotRunning) }
    }

    private func ensureStarted() throws {
        try stateQueue.sync {
            if process?.isRunning == true {
                return
            }
            guard FileManager.default.isExecutableFile(atPath: hostExecutableURL.path) else {
                throw ConnectionError.hostNotFound
            }

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            let process = Process()
            process.executableURL = hostExecutableURL
            process.arguments = ["--stdio"]
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            self.process = process
            self.stdinHandle = stdinPipe.fileHandleForWriting
            startReadLoop(stdoutHandle: stdoutPipe.fileHandleForReading, stderrHandle: stderrPipe.fileHandleForReading)
        }
    }

    private func startReadLoop(stdoutHandle: FileHandle, stderrHandle: FileHandle) {
        stdoutTask?.cancel()
        stdoutTask = Task { [weak self] in
            guard let self else { return }
            async let stderrDrain: Void = Self.drain(stderrHandle)
            do {
                for try await line in stdoutHandle.bytes.lines {
                    self.handle(line: String(line))
                }
            } catch {
                self.failAll(with: error)
            }
            _ = await stderrDrain
        }
    }

    private static func drain(_ handle: FileHandle) async {
        do {
            for try await _ in handle.bytes.lines {
                continue
            }
        } catch {
            return
        }
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let response = try? JSONDecoder().decode(HostResponse.self, from: data), response.kind == "response" {
            let continuation: CheckedContinuation<Data, Error>? = stateQueue.sync {
                pendingResponses.removeValue(forKey: response.id)
            }
            if let continuation {
                if let error = response.error {
                    continuation.resume(throwing: ConnectionError.remoteError(error))
                } else if let result = response.result?.dataValue {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: ConnectionError.invalidResponse)
                }
            }
            return
        }
    }

    private func writeRequest(id: String, method: String, params: JSONValue) throws {
        let stdinHandle: FileHandle? = stateQueue.sync { self.stdinHandle }
        guard let stdinHandle else { throw ConnectionError.hostNotRunning }
        let data = try JSONEncoder().encode(HostRequest(id: id, method: method, params: params))
        guard var text = String(data: data, encoding: .utf8) else {
            throw ConnectionError.invalidResponse
        }
        text.append("\n")
        if let writeData = text.data(using: .utf8) {
            try stdinHandle.write(contentsOf: writeData)
        }
    }

    private func failAll(with error: Error) {
        let responses: [CheckedContinuation<Data, Error>] = stateQueue.sync {
            let responses = Array(pendingResponses.values)
            pendingResponses.removeAll()
            return responses
        }
        responses.forEach { $0.resume(throwing: error) }
    }
}
