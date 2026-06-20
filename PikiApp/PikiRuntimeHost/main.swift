import Foundation

private struct HostRequest: Codable {
    let id: String
    let method: String
    let params: JSONValue?
}

private struct HostResponse: Encodable {
    let kind = "response"
    let id: String
    let result: JSONValue?
    let error: String?
}

private enum JSONValue: Codable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct LaunchError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

func runHost() {
    if CommandLine.arguments.contains("--health-check") {
        emit(json: HostResponse(id: "health", result: .object(["ok": .bool(true)]), error: nil))
        return
    }

    if CommandLine.arguments.contains("--stdio") {
        runStdio()
        return
    }

    RunLoop.main.run()
}

func runStdio() {
    let worker = RuntimeHostProxy.makeWorkerProcess()
    guard let stdinPipe = worker.standardInput as? Pipe,
          let stdoutPipe = worker.standardOutput as? Pipe,
          let stderrPipe = worker.standardError as? Pipe
    else {
        emitError("Unable to create worker pipes.")
        return
    }

    do {
        try worker.run()
    } catch {
        emitError(error.localizedDescription)
        return
    }

    let forwarder = Task {
        async let workerStdout: Void = forwardLines(from: stdoutPipe.fileHandleForReading)
        async let workerStderr: Void = drain(stderrPipe.fileHandleForReading)
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let data = String(line).data(using: .utf8),
                      let request = try? JSONDecoder().decode(HostRequest.self, from: data) else {
                    continue
                }
                if let payload = try? JSONEncoder().encode(request),
                   let text = String(data: payload, encoding: .utf8) {
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8))
                }
            }
        } catch {
            emitError(error.localizedDescription)
        }
        _ = await workerStdout
        _ = await workerStderr
    }

    withExtendedLifetime(forwarder) {
        RunLoop.current.run()
    }
}

private enum RuntimeHostProxy {
    static func makeWorkerProcess() -> Process {
        let process = Process()
        process.executableURL = workerExecutableURL()
        process.arguments = [
            "-m", "agent_service.runtime.cli", "stdio",
            "--db-path", runtimePath("agent_service.sqlite3"),
            "--runtime-config-path", runtimePath("runtime-config.json"),
            "--staging-root", runtimePath("task-staging")
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PYTHONUNBUFFERED": "1"],
            uniquingKeysWith: { _, new in new }
        )
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    private static func workerExecutableURL() -> URL {
        URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func runtimePath(_ filename: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".piki", isDirectory: true)
            .appendingPathComponent(filename)
            .path
    }
}

private func forwardLines(from handle: FileHandle) async {
    do {
        for try await line in handle.bytes.lines {
            print(String(line))
            fflush(stdout)
        }
    } catch {
        emitError(error.localizedDescription)
    }
}

private func drain(_ handle: FileHandle) async {
    do {
        for try await _ in handle.bytes.lines {
            continue
        }
    } catch {
        return
    }
}

private func emitError(_ message: String) {
    emit(json: HostResponse(id: "error", result: nil, error: message))
}

private func emit<T: Encodable>(json: T) {
    guard let data = try? JSONEncoder().encode(json), let text = String(data: data, encoding: .utf8) else { return }
    print(text)
    fflush(stdout)
}

runHost()
