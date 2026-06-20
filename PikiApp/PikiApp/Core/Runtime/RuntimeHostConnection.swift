import Foundation
import os

actor RuntimeHostConnection {
    private struct WorkerNotification: Decodable {
        let kind: String
        let event: TaskEvent
    }
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
    private struct TaskEventsEnvelope: Decodable {
        let events: [TaskEvent]
        let cursor: String?
        let hasMore: Bool?
    }

    enum ConnectionError: Error, LocalizedError {
        case hostNotFound, hostNotRunning, invalidResponse, timeout
        case remoteError(String)
        var errorDescription: String? {
            switch self {
            case .hostNotFound: "PikiRuntimeHost was not found."
            case .hostNotRunning: "PikiRuntimeHost is not running."
            case .invalidResponse: "Invalid response from runtime host."
            case .timeout: "Request to runtime host timed out."
            case .remoteError(let m): m
            }
        }
        var shouldRetry: Bool {
            switch self {
            case .hostNotFound, .hostNotRunning: true
            case .remoteError: true
            case .timeout, .invalidResponse: false
            }
        }
    }

    private static let logger = Logger(subsystem: "com.piki.app", category: "RuntimeHost")
    private let hostExecutableURL: URL
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readLoopTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var lineConsumerTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<Data, Error>] = [:]
    private var taskSignals: [String: Int] = [:]
    private var taskSignalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var lastStderrOutput = ""
    init(hostExecutableURL: URL) { self.hostExecutableURL = hostExecutableURL }

    nonisolated static func locateHostExecutable() -> URL? {
        let processDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var candidates = [
            processDir.appendingPathComponent("PikiRuntimeHost"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PikiRuntimeHost"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PikiRuntimeHost"),
            Bundle.main.resourceURL?.appendingPathComponent("PikiRuntimeHost"),
        ].compactMap { $0 }
        if let srcRoot = findProjectRoot() {
            candidates.append(srcRoot.appendingPathComponent(".build/debug/PikiRuntimeHost"))
            candidates.append(srcRoot.appendingPathComponent(".build/release/PikiRuntimeHost"))
        }
        for url in candidates {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private nonisolated static func findProjectRoot() -> URL? {
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<10 {
            let info = dir.appendingPathComponent("info.plist")
            if let data = try? Data(contentsOf: info),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let workspace = plist["WorkspacePath"] as? String {
                let wsURL = URL(fileURLWithPath: workspace)
                if FileManager.default.fileExists(atPath: wsURL.appendingPathComponent("Package.swift").path) {
                    return wsURL
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    func call(method: String, params: JSONValue = .object([:])) async throws -> Data {
        try ensureStarted()
        let id = UUID().uuidString
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: .seconds(30))
            await self?.timeoutRequest(id: id)
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            do {
                try writeRequest(id: id, method: method, params: params)
            } catch {
                pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: TaskEvent.self, throwing: Error.self)
        let pollTask = Task { [weak self] in
            guard let self else { return }
            var cursor: String?
            let terminalTypes: Set<String> = ["task.completed", "task.cancelled", "task.failed"]
            while !Task.isCancelled {
                do {
                    let p: JSONValue = cursor.map { .object(["task_id": .string(taskId), "cursor": .string($0)]) }
                        ?? .object(["task_id": .string(taskId)])
                    let data = try await self.call(method: "task_events", params: p)
                    let envelope = try JSONDecoder().decode(TaskEventsEnvelope.self, from: data)
                    for event in envelope.events { cont.yield(event) }
                    if let c = envelope.cursor { cursor = c }
                    if envelope.events.contains(where: { terminalTypes.contains($0.type) }) {
                        break
                    }
                    if envelope.events.isEmpty { await self.waitForTaskSignal(taskId: taskId) }
                } catch is CancellationError { break }
                catch { cont.finish(throwing: error); return }
            }
            cont.finish()
            await self.cancelTaskSignalWaiters(taskId: taskId)
        }
        cont.onTermination = { _ in pollTask.cancel() }
        return stream
    }

    func stop() {
        readLoopTask?.cancel(); readLoopTask = nil
        stderrTask?.cancel(); stderrTask = nil
        lineConsumerTask?.cancel(); lineConsumerTask = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; stdinHandle = nil
        let responses = pendingResponses; pendingResponses.removeAll()
        for (_, c) in responses { c.resume(throwing: ConnectionError.hostNotRunning) }
        let waiters = taskSignalWaiters; taskSignalWaiters.removeAll()
        for (_, list) in waiters { list.forEach { $0.resume() } }
    }

    // MARK: - Private

    private func ensureStarted() throws {
        if process?.isRunning == true { return }
        cleanupProcess()
        guard FileManager.default.isExecutableFile(atPath: hostExecutableURL.path) else {
            Self.logger.error("Host not found at \(self.hostExecutableURL.path)")
            throw ConnectionError.hostNotFound
        }
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let proc = Process()
        proc.executableURL = hostExecutableURL
        proc.arguments = ["--stdio"]
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        try proc.run()
        Self.logger.info("Launched host pid=\(proc.processIdentifier)")
        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        startReadLoop(stdoutHandle: stdoutPipe.fileHandleForReading)
        startStderrCapture(stderrHandle: stderrPipe.fileHandleForReading)
    }

    private func cleanupProcess() {
        readLoopTask?.cancel(); readLoopTask = nil
        stderrTask?.cancel(); stderrTask = nil
        lineConsumerTask?.cancel(); lineConsumerTask = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; stdinHandle = nil
    }

    private func startReadLoop(stdoutHandle: FileHandle) {
        let (stream, streamCont) = AsyncStream.makeStream(of: String.self)
        readLoopTask = Task.detached { [weak self] in
            do {
                for try await line in stdoutHandle.bytes.lines {
                    if Task.isCancelled { break }
                    streamCont.yield(String(line))
                }
            } catch {}
            streamCont.finish()
            await self?.handleEOF()
        }
        lineConsumerTask = Task { [weak self] in
            for await line in stream {
                guard let self else { break }
                await self.handleLine(line)
            }
        }
    }

    private func startStderrCapture(stderrHandle: FileHandle) {
        stderrTask = Task.detached { [weak self] in
            do {
                for try await line in stderrHandle.bytes.lines {
                    if Task.isCancelled { break }
                    await self?.appendStderr(String(line))
                }
            } catch {}
        }
    }

    private func appendStderr(_ line: String) {
        lastStderrOutput += line + "\n"
        if lastStderrOutput.count > 4096 {
            lastStderrOutput = String(lastStderrOutput.suffix(2048))
        }
        Self.logger.warning("RuntimeHost stderr: \(line)")
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let notification = try? JSONDecoder().decode(WorkerNotification.self, from: data),
           notification.kind == "event" {
            signalTask(notification.event.taskId)
            return
        }
        if let response = try? JSONDecoder().decode(HostResponse.self, from: data),
           response.kind == "response" {
            guard let continuation = pendingResponses.removeValue(forKey: response.id) else { return }
            if let error = response.error {
                continuation.resume(throwing: ConnectionError.remoteError(error))
            } else if let result = response.result?.dataValue {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: ConnectionError.invalidResponse)
            }
        }
    }

    private func handleEOF() {
        let detail = lastStderrOutput.isEmpty ? "" : " stderr: \(lastStderrOutput.prefix(500))"
        Self.logger.error("RuntimeHost stdout EOF.\(detail)")
        let responses = pendingResponses; pendingResponses.removeAll()
        let message = lastStderrOutput.isEmpty
            ? "PikiRuntimeHost exited unexpectedly."
            : "PikiRuntimeHost exited: \(lastStderrOutput.prefix(300))"
        for (_, c) in responses {
            c.resume(throwing: ConnectionError.remoteError(message))
        }
        process = nil; stdinHandle = nil
    }

    private func timeoutRequest(id: String) {
        if let cont = pendingResponses.removeValue(forKey: id) {
            cont.resume(throwing: ConnectionError.timeout)
        }
    }

    private func writeRequest(id: String, method: String, params: JSONValue) throws {
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

    private func signalTask(_ taskId: String) {
        taskSignals[taskId, default: 0] += 1
        if let waiters = taskSignalWaiters.removeValue(forKey: taskId) {
            waiters.forEach { $0.resume() }
        }
    }

    private func waitForTaskSignal(taskId: String) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let count = taskSignals[taskId], count > 0 {
                    taskSignals[taskId] = count - 1
                    continuation.resume()
                } else {
                    taskSignalWaiters[taskId, default: []].append(continuation)
                }
            }
        } onCancel: { [weak self] in
            Task { [weak self] in
                await self?.cancelTaskSignalWaiters(taskId: taskId)
            }
        }
    }

    private func cancelTaskSignalWaiters(taskId: String) {
        if let waiters = taskSignalWaiters.removeValue(forKey: taskId) {
            waiters.forEach { $0.resume() }
        }
    }
}