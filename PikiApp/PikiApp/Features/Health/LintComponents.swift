import SwiftUI

struct LintCTACard: View {
    let isRunning: Bool
    let onRunLint: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lint your vault")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Check for orphan pages, broken links, stale content, and knowledge gaps")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onRunLint) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("Run Lint")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isRunning)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.primary, Theme.primaryDark],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
    }
}

struct LintIssueRow: View {
    let issue: LintIssue

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(issue.severity.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(issue.type)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Theme.textSecondary)
                        .background(Theme.border.opacity(0.3))
                        .clipShape(.capsule)
                    if let page = issue.affectedPage {
                        Text(page)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
