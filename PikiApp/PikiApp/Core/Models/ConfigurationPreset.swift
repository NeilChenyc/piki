import Foundation

struct ConfigurationPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var agentModel: String
    var anthropicBaseURL: String
    var apiKey: String
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        agentModel: String,
        anthropicBaseURL: String,
        apiKey: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.agentModel = agentModel
        self.anthropicBaseURL = anthropicBaseURL
        self.apiKey = apiKey
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
