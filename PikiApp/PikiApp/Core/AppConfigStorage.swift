import Foundation

struct OnboardingConfig: Codable, Equatable {
    var setupCompleted: Bool = false
    var setupSkipped: Bool = false
    var showcaseDismissed: Bool = false
    var completedSteps: Set<String> = []

    init(setupCompleted: Bool = false, setupSkipped: Bool = false, showcaseDismissed: Bool = false, completedSteps: Set<String> = []) {
        self.setupCompleted = setupCompleted
        self.setupSkipped = setupSkipped
        self.showcaseDismissed = showcaseDismissed
        self.completedSteps = completedSteps
    }

    private enum CodingKeys: String, CodingKey {
        case setupCompleted, setupSkipped, showcaseDismissed, completedSteps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? false
        self.setupSkipped = try container.decodeIfPresent(Bool.self, forKey: .setupSkipped) ?? false
        self.showcaseDismissed = try container.decodeIfPresent(Bool.self, forKey: .showcaseDismissed) ?? false
        self.completedSteps = try container.decodeIfPresent(Set<String>.self, forKey: .completedSteps) ?? []
    }
}

struct AppConfig: Codable, Equatable {
    var vaultPath: String?
    var activePresetId: String?
    var onboarding: OnboardingConfig = OnboardingConfig()

    init(vaultPath: String? = nil, activePresetId: String? = nil, onboarding: OnboardingConfig = OnboardingConfig()) {
        self.vaultPath = vaultPath
        self.activePresetId = activePresetId
        self.onboarding = onboarding
    }

    private enum CodingKeys: String, CodingKey {
        case vaultPath, activePresetId, onboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath)
        self.activePresetId = try container.decodeIfPresent(String.self, forKey: .activePresetId)
        self.onboarding = try container.decodeIfPresent(OnboardingConfig.self, forKey: .onboarding) ?? OnboardingConfig()
    }
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
        var config = (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()

        if !config.onboarding.setupCompleted,
           config.vaultPath != nil,
           !PresetStorage.load().isEmpty {
            config.onboarding.setupCompleted = true
            config.onboarding.completedSteps = ["vault", "api"]
            save(config)
        }

        return config
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
