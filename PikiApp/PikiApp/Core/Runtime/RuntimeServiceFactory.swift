import Foundation

@MainActor
enum RuntimeServiceFactory {
    static func makeDefault() -> any RuntimeServiceProtocol {
        if let native = NativeRuntimeService.makeDefault() {
            return native
        }
        return HTTPRuntimeService(baseURL: URL(string: "http://127.0.0.1:8000")!)
    }
}
