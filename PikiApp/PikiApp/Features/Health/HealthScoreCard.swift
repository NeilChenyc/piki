import SwiftUI

struct OverviewMetricCard: View {
    let metric: OverviewMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text(metric.value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(metric.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

struct HealthDimensionCard: View {
    let dimension: HealthDimension

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dimension.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(dimension.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HealthStatusBadge(title: dimension.status.title, color: dimension.status.color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(dimension.issueCount.map(String.init) ?? "--")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("个问题")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

struct LintSummaryCard: View {
    let summary: LintSummary?
    let breakdown: [IssueBreakdownItem]
    let isLoading: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary {
                LazyVGrid(columns: columns, spacing: 12) {
                    SummaryMetricTile(title: "扫描页面", value: "\(summary.scannedFiles)")
                    SummaryMetricTile(title: "总问题数", value: "\(summary.totalIssues)")
                    SummaryMetricTile(title: "可修复问题", value: "\(summary.fixableIssues)")
                    SummaryMetricTile(title: "高优先级", value: "\(summary.highPriorityIssues)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("关键问题概览")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("最近检查 \(summary.generatedAtText)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if breakdown.isEmpty {
                        Text("本次检查没有发现明显结构问题。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(breakdown) { item in
                                BreakdownChip(item: item)
                            }
                        }
                    }
                }
            } else if isLoading {
                HealthEmptyStateCard(
                    title: "正在检查知识库",
                    message: "会自动拉取最近维护记录并运行 lint，完成后这里会展示扫描摘要。"
                )
            } else {
                HealthEmptyStateCard(
                    title: "尚未检查",
                    message: "先展示知识库规模数据；运行 lint 后再补充结构问题、缺口和可修复项。"
                )
            }
        }
        .padding(16)
        .cardStyle()
    }
}

struct SummaryMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.subtleFill)
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct BreakdownChip: View {
    let item: IssueBreakdownItem

    var body: some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
            Text("\(item.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.subtleFill)
        .clipShape(.capsule)
    }
}

struct HealthStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(.capsule)
    }
}

struct HealthEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cardStyle()
    }
}
