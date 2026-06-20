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

private struct RuntimeBundlePaths: Decodable {
    let python: String
    let sitePackages: String

    enum CodingKeys: String, CodingKey {
        case python
        case sitePackages = "site_packages"
    }
}

private func runtimeResourcesRoot() -> URL {
    if let executable = Bundle.main.executableURL {
        let bundleResources = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: bundleResources.path) {
            return bundleResources
        }
        return executable.deletingLastPathComponent().appendingPathComponent("Resources")
    }
    return URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
}

private func loadRuntimeBundlePaths() -> RuntimeBundlePaths? {
    let url = runtimeResourcesRoot().appendingPathComponent("runtime-paths.json")
    guard FileManager.default.isReadableFile(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode(RuntimeBundlePaths.self, from: data)
    else {
        return nil
    }
    return value
}

private struct LaunchError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

func runHost() {
    if CommandLine.arguments.contains("--health-check") {
        let ok = runtimeResourcesRoot().appendingPathComponent("runtime-paths.json")
        emit(json: HostResponse(id: "health", result: .object(["ok": .bool(FileManager.default.fileExists(atPath: ok.path))]), error: nil))
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
        let command = workerCommand()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        if let bundle = loadRuntimeBundlePaths() {
            let resourceRoot = runtimeResourcesRoot()
            let pythonHome = resourceRoot.appendingPathComponent(bundle.python)
            let sitePackages = resourceRoot.appendingPathComponent(bundle.sitePackages)
            let pythonPath = [sitePackages.path, environment["PYTHONPATH"]].compactMap { $0 }.joined(separator: ":")
            environment["PYTHONHOME"] = pythonHome.path
            environment["PYTHONPATH"] = pythonPath
            environment["PIKI_BUNDLE_ROOT"] = resourceRoot.path
        }
        process.environment = environment
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    private static func workerCommand() -> (executableURL: URL, arguments: [String]) {
        let resourceRoot = runtimeResourcesRoot()
        if let bundle = loadRuntimeBundlePaths() {
            for candidate in bundledPythonCandidates(resourceRoot: resourceRoot, bundle: bundle) {
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return (candidate, [
                        "-m", "agent_service.runtime.cli", "stdio",
                        "--db-path", runtimePath("agent_service.sqlite3"),
                        "--runtime-config-path", runtimePath("runtime-config.json"),
                        "--staging-root", runtimePath("task-staging")
                    ])
                }
            }
        }
        return (URL(fileURLWithPath: "/usr/bin/false"), [])
    }

    private static func bundledPythonCandidates(resourceRoot: URL, bundle: RuntimeBundlePaths) -> [URL] {
        let pythonRoot = resourceRoot.appendingPathComponent(bundle.python)
        return [
            pythonRoot.appendingPathComponent("bin/python"),
            pythonRoot.appendingPathComponent("bin/python3"),
            pythonRoot.appendingPathComponent("bin/python3"),
            pythonRoot.appendingPathComponent("bin/python3.12"),
        ]
    }

    private static func runtimePath(_ filename: String) -> String {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".piki", isDirectory: true)
        let path = base.appendingPathComponent(filename)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if filename.contains("/") {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return path.path
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
