import SwiftUI

@Observable
@MainActor
final class HealthViewModel {
    var healthScores: [HealthScore] = HealthScore.defaults
    var trendData: [HealthTrendPoint] = []
    var lintIssues: [LintIssue] = []
    var affectedPages: [String] = []
    var isLintRunning = false
    var errorMessage: String?

    func runLint(appState: AppState) {
        guard appState.isConnected else {
            errorMessage = appState.serviceErrorMessage ?? "Agent Service is disconnected."
            return
        }
        guard let vaultPath = appState.vaultPath else {
            errorMessage = "Select a vault before running lint."
            return
        }

        isLintRunning = true
        errorMessage = nil
        Task {
            do {
                let result = try await appState.apiClient.runLint(vaultPath: vaultPath.path(percentEncoded: false))
                lintIssues = result.issues.map(LintIssue.init(dto:))
                affectedPages = Array(Set(result.issues.map(\.path))).sorted()
                healthScores = HealthScore.fromLintResult(result)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLintRunning = false
        }
    }
}

struct HealthScore: Identifiable {
    let id: String
    let title: String
    let value: Double
    let trend: Trend

    enum Trend {
        case up, down, stable
        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .stable: "minus"
            }
        }
        var color: Color {
            switch self {
            case .up: .green
            case .down: .red
            case .stable: .gray
            }
        }
    }

    static let defaults: [HealthScore] = [
        HealthScore(id: "overall", title: "Overall Health", value: 0, trend: .stable),
        HealthScore(id: "content", title: "Content Health", value: 0, trend: .stable),
        HealthScore(id: "integrity", title: "Wiki Integrity", value: 0, trend: .stable),
        HealthScore(id: "links", title: "Search & Links", value: 0, trend: .stable),
    ]

    static func fromLintResult(_ result: LintResultDTO) -> [HealthScore] {
        let issueCount = result.issues.count
        let score = max(0, 100 - Double(issueCount * 5))
        let linkIssues = result.issues.filter { $0.kind == "broken_link" }.count
        let contentIssues = result.issues.filter { ["thin_page", "stale_page", "knowledge_gap"].contains($0.kind) }.count
        let integrityIssues = result.issues.filter { ["missing_frontmatter", "missing_heading", "duplicate_title", "missing_index_entry", "orphan_page"].contains($0.kind) }.count

        return [
            HealthScore(id: "overall", title: "Overall Health", value: score, trend: .stable),
            HealthScore(id: "content", title: "Content Health", value: max(0, 100 - Double(contentIssues * 8)), trend: .stable),
            HealthScore(id: "integrity", title: "Wiki Integrity", value: max(0, 100 - Double(integrityIssues * 8)), trend: .stable),
            HealthScore(id: "links", title: "Search & Links", value: max(0, 100 - Double(linkIssues * 12)), trend: .stable),
        ]
    }
}

struct HealthTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
}

struct LintIssue: Identifiable {
    let id: String
    let description: String
    let severity: Severity
    let type: String
    let affectedPage: String?

    enum Severity: String {
        case high, medium, low
        var color: Color {
            switch self {
            case .high: .red
            case .medium: .orange
            case .low: .yellow
            }
        }
    }

    init(dto: LintIssueDTO) {
        id = dto.id
        description = dto.message
        severity = switch dto.severity {
        case "error": .high
        case "warning": .medium
        default: .low
        }
        type = dto.kind
        affectedPage = dto.path
    }
}
