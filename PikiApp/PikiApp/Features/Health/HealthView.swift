import SwiftUI
import Charts

struct HealthView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = HealthViewModel()

    var body: some View {
        HSplitView {
            // Main dashboard area
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    Text("Vault Health")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    // Score cards
                    HStack(spacing: 16) {
                        ForEach(viewModel.healthScores) { score in
                            HealthScoreCard(score: score)
                        }
                    }

                    // Trend chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Vault health over time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        HealthTrendChart(data: viewModel.trendData)
                            .frame(height: 200)
                    }
                    .padding(20)
                    .cardStyle()

                    // Lint CTA
                    LintCTACard(
                        isRunning: viewModel.isLintRunning,
                        onRunLint: {
                            viewModel.runLint(appState: appState)
                        }
                    )

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.error)
                    }
                }
                .padding(24)
            }

            // Right panel - prioritized tasks
            VStack(alignment: .leading, spacing: 16) {
                Text("Prioritized Tasks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.lintIssues) { issue in
                            LintIssueRow(issue: issue)
                        }
                    }
                }

                Divider()

                Text("Affected Pages")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.affectedPages, id: \.self) { page in
                            Text(page)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}
