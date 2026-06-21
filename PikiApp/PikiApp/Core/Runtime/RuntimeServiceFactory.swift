import Foundation

@MainActor
enum RuntimeServiceFactory {
    static func makeDefault() -> any RuntimeServiceProtocol {
        HTTPRuntimeService(baseURL: URL(string: "http://127.0.0.1:8782")!)
    }
}

enum RuntimeError: LocalizedError {
    case runtimeHostUnavailable

    var errorDescription: String? {
        "Piki Agent Service is unavailable."
    }
}
