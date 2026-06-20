import Foundation

struct AppConfig: Codable, Equatable {
    var serviceBaseURL: String = "http://127.0.0.1:8000"
    var vaultPath: String?
    var activePresetId: String?
}

enum AppConfigStorage {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appending(path: "Piki", directoryHint: .isDirectory)
        return dir.appending(path: "app-config.json")
    }

    static func load() -> AppConfig {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    static func save(_ config: AppConfig) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
