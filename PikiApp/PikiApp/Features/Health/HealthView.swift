import SwiftUI

struct HealthView: View {
    @Environment(AppState.self) private var appState
    @Environment(HealthViewModel.self) private var viewModel

    private let dimensionColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top),
    ]

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if appState.vaultPath == nil {
                    HealthEmptyStateCard(
                        title: "尚未选择知识库",
                        message: "先在设置或首页选择一个 vault，Health 页面才会展示知识库规模和 lint 结果。"
                    )
                } else if viewModel.isLoading && !viewModel.hasOverview && viewModel.lintSummary == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载健康数据...")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(24)
                } else {
                    if viewModel.hasOverview {
                        section(title: "知识库概览") {
                            HealthOverviewList(metrics: viewModel.overviewMetrics)
                        }
                    }

                    section(title: "健康摘要", subtitle: "结构、链接与复查状态的轻量总览") {
                        LazyVGrid(columns: dimensionColumns, spacing: 16) {
                            ForEach(viewModel.healthDimensions) { dimension in
                                HealthDimensionCard(dimension: dimension)
                            }
                        }
                    }

                    section(title: "当前检查摘要", subtitle: "只保留知识库本体与 lint 结果，不引入运行时诊断") {
                        LintSummaryCard(
                            summary: viewModel.lintSummary,
                            breakdown: viewModel.issueBreakdown,
                            isLoading: viewModel.isLoading || viewModel.isLintRunning
                        )
                    }

                    LintCTACard(
                        isRunning: viewModel.isLoading || viewModel.isLintRunning,
                        isFixRunning: viewModel.isFixRunning,
                        canApplyFixes: viewModel.canApplyFixes,
                        onRunLint: {
                            viewModel.rerunLint(appState: appState)
                        },
                        onApplyFixes: {
                            viewModel.applyFixes(appState: appState)
                        }
                    )

                    section(title: "关键问题") {
                        criticalIssuesSection
                    }

                    section(title: "受影响页面") {
                        affectedPagesSection
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(24)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryPanelBackground)
        .task(id: taskIdentifier) {
            await self.viewModel.loadIfNeeded(appState: appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("知识库健康")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var criticalIssuesSection: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 16) {
            if appState.vaultPath != nil {
                Picker("问题筛选", selection: $viewModel.selectedFilter) {
                    ForEach(IssueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            issuesSection
        }
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.vaultPath == nil {
                SidebarEmptyState(message: "选择知识库后可查看问题列表。")
            } else if (viewModel.isLoading || viewModel.isLintRunning) && viewModel.lintSummary == nil {
                SidebarLoadingState(message: "正在加载当前 health 数据…")
            } else if viewModel.lintSummary == nil {
                SidebarEmptyState(message: "尚未拿到 lint 结果，点击 Run lint 可重新检查。")
            } else if viewModel.filteredIssues.isEmpty {
                let message = switch viewModel.selectedFilter {
                case .all:
                    "当前没有发现问题。"
                case .fixable:
                    "当前没有可自动修复的问题。"
                case .highPriority:
                    "当前没有高优先级问题。"
                }
                SidebarEmptyState(message: message)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredIssues) { issue in
                        LintIssueRow(issue: issue)
                    }
                }
            }
        }
    }

    private var affectedPagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.vaultPath == nil {
                SidebarEmptyState(message: "选择知识库后可查看受影响页面。")
            } else if viewModel.affectedPages.isEmpty {
                SidebarEmptyState(message: viewModel.lintSummary == nil ? "等待 lint 结果…" : "当前没有受影响页面。")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.visibleAffectedPages) { page in
                        AffectedPageRow(page: page)
                    }
                }
            }
        }
    }

    private var taskIdentifier: String {
        let vaultPath = appState.vaultPath?.path(percentEncoded: false) ?? "none"
        return "\(vaultPath)|\(appState.isConnected)"
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            content()
        }
    }
}
