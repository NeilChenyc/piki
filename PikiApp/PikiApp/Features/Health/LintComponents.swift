import SwiftUI

struct LintCTACard: View {
    let isRunning: Bool
    let isFixRunning: Bool
    let canApplyFixes: Bool
    let onRunLint: () -> Void
    let onApplyFixes: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("轻量维护")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Run lint 用来重新检查结构、链接和复查状态；Apply low-risk fixes 只处理当前支持的低风险自动修复。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onRunLint) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("Run lint")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .disabled(isRunning || isFixRunning)

                Button(action: onApplyFixes) {
                    if isFixRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("Apply low-risk fixes")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(isRunning || isFixRunning || !canApplyFixes)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.accent, Theme.accentDark],
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(issue.severity.color)
                    .frame(width: 8, height: 8)

                Text(issue.kindTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HealthStatusBadge(title: "\(issue.severity.title)优先级", color: issue.severity.color)

                if issue.fixable {
                    Text("可修复")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.75))
                        .clipShape(.capsule)
                }

                Spacer()
            }

            Text(issue.description)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let page = issue.affectedPage {
                Label(page, systemImage: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border.opacity(0.4), lineWidth: 1)
        )
    }
}

struct AffectedPageRow: View {
    let page: AffectedPageSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(page.path)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("\(page.issueCount) 个问题")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border.opacity(0.4), lineWidth: 1)
        )
    }
}

struct SidebarEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.elevatedCardBackground)
            .clipShape(.rect(cornerRadius: 10))
    }
}

struct SidebarLoadingState: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 10))
    }
}
