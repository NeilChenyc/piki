import Foundation
import SwiftUI

@Observable
@MainActor
final class HealthViewModel {
    var overviewMetrics: [OverviewMetric] = []
    var healthDimensions: [HealthDimension] = HealthDimension.placeholder
    var lintSummary: LintSummary?
    var issueBreakdown: [IssueBreakdownItem] = []
    var lintIssues: [LintIssue] = []
    var affectedPages: [AffectedPageSummary] = []
    var selectedFilter: IssueFilter = .all
    var isLoading = false
    var isLintRunning = false
    var isFixRunning = false
    var errorMessage: String?
    var hasLoaded = false

    private var loadedVaultPath: String?
    private var loadedConnectionState = false
    private var latestLintResult: LintResultDTO?
    private var latestMaintenanceDate: Date?
    private var latestLintDate: Date?

    var filteredIssues: [LintIssue] {
        switch selectedFilter {
        case .all:
            lintIssues
        case .fixable:
            lintIssues.filter(\.fixable)
        case .highPriority:
            lintIssues.filter { $0.severity == .high }
        }
    }

    var visibleAffectedPages: [AffectedPageSummary] {
        Array(affectedPages.prefix(8))
    }

    var canApplyFixes: Bool {
        !(latestLintResult?.fixableIssueIds?.isEmpty ?? true)
    }

    var hasOverview: Bool {
        !overviewMetrics.isEmpty
    }

    func loadIfNeeded(appState: AppState) async {
        let currentVaultPath = appState.vaultPath?.path(percentEncoded: false)
        let shouldReload = loadedVaultPath != currentVaultPath
            || loadedConnectionState != appState.isConnected
            || !hasLoaded
        guard shouldReload else { return }

        loadedVaultPath = currentVaultPath
        loadedConnectionState = appState.isConnected
        await reload(appState: appState, mode: .initial)
    }

    func rerunLint(appState: AppState) {
        Task {
            await reload(appState: appState, mode: .manualLint)
        }
    }

    func applyFixes(appState: AppState) {
        Task {
            await applyLowRiskFixes(appState: appState)
        }
    }

    private func reload(appState: AppState, mode: ReloadMode) async {
        hasLoaded = true
        errorMessage = nil

        guard let vaultURL = appState.vaultPath else {
            resetForMissingVault()
            return
        }

        let vaultPath = vaultURL.path(percentEncoded: false)
        refreshOverview(for: vaultURL)
        setLoading(true, for: mode)
        defer { setLoading(false, for: mode) }

        if appState.isConnected {
            await loadRecentMaintenance(
                client: appState.apiClient,
                vaultURL: vaultURL,
                vaultPath: vaultPath
            )
            await loadLint(
                client: appState.apiClient,
                vaultURL: vaultURL,
                vaultPath: vaultPath
            )
        } else {
            clearLintState()
            errorMessage = "当前仅展示本地知识库概览；lint 暂时不可用。"
        }
    }

    private func applyLowRiskFixes(appState: AppState) async {
        guard appState.isConnected else {
            errorMessage = "当前无法执行自动修复，请稍后重试。"
            return
        }

        guard let vaultPath = appState.vaultPath?.path(percentEncoded: false) else {
            resetForMissingVault()
            return
        }

        let issueIds = latestLintResult?.fixableIssueIds ?? []
        guard !issueIds.isEmpty else { return }

        isFixRunning = true
        errorMessage = nil
        defer { isFixRunning = false }

        do {
            try await appState.apiClient.fixLint(vaultPath: vaultPath, issueIds: issueIds)
            await reload(appState: appState, mode: .afterFix)
        } catch {
            errorMessage = "低风险修复执行失败，请稍后重试。"
        }
    }

    private func loadRecentMaintenance(client: APIClient, vaultURL: URL, vaultPath: String) async {
        do {
            let entries = try await client.recentJournal(limit: 10, vaultPath: vaultPath)
            latestMaintenanceDate = entries
                .compactMap { parseDate($0.createdAt) }
                .max()
            refreshOverview(for: vaultURL)
        } catch {
            errorMessage = "最近维护时间读取失败，已展示其余健康数据。"
        }
    }

    private func loadLint(client: APIClient, vaultURL: URL, vaultPath: String) async {
        do {
            let result = try await client.runLint(vaultPath: vaultPath)
            applyLintResult(result, vaultURL: vaultURL)
        } catch {
            clearLintState()
            errorMessage = "知识库检查失败，请稍后重试。"
        }
    }

    private func refreshOverview(for vaultURL: URL) {
        overviewMetrics = buildOverview(from: vaultURL).metrics
    }

    private func buildOverview(from vaultURL: URL) -> VaultOverview {
        VaultOverview(
            totalPages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki", isDirectory: true)),
            totalSources: countRegularFiles(in: vaultURL.appendingPathComponent("raw/sources", isDirectory: true)),
            sourcePages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki/sources", isDirectory: true)),
            conceptPages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki/concepts", isDirectory: true)),
            entityPages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki/entities", isDirectory: true)),
            domainPages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki/domains", isDirectory: true)),
            synthesisPages: countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki/synthesis", isDirectory: true)),
            latestMaintenance: latestMaintenanceDate,
            latestCheck: latestLintDate
        )
    }

    private func applyLintResult(_ result: LintResultDTO, vaultURL: URL) {
        latestLintResult = result
        latestLintDate = parseDate(result.generatedAt)
        lintSummary = LintSummary(result: result)
        healthDimensions = HealthDimension.fromLintResult(result)
        lintIssues = result.issues
            .map(LintIssue.init(dto:))
            .sorted(by: lintIssueComparator)
        affectedPages = AffectedPageSummary.fromIssues(lintIssues)
        issueBreakdown = IssueBreakdownItem.fromIssues(lintIssues)
        refreshOverview(for: vaultURL)
    }

    private func resetForMissingVault() {
        loadedVaultPath = nil
        latestMaintenanceDate = nil
        latestLintDate = nil
        overviewMetrics = []
        clearLintState()
        errorMessage = nil
    }

    private func clearLintState() {
        latestLintResult = nil
        lintSummary = nil
        healthDimensions = HealthDimension.placeholder
        lintIssues = []
        affectedPages = []
        issueBreakdown = []
        selectedFilter = .all
    }

    private func setLoading(_ isActive: Bool, for mode: ReloadMode) {
        switch mode {
        case .initial:
            isLoading = isActive
        case .manualLint:
            isLintRunning = isActive
        case .afterFix:
            isLintRunning = isActive
        }
    }

    private var lintIssueComparator: (LintIssue, LintIssue) -> Bool {
        { lhs, rhs in
            if lhs.severity.rank != rhs.severity.rank {
                return lhs.severity.rank < rhs.severity.rank
            }
            if lhs.fixable != rhs.fixable {
                return lhs.fixable && !rhs.fixable
            }
            if lhs.kindTitle != rhs.kindTitle {
                return lhs.kindTitle < rhs.kindTitle
            }
            return lhs.description < rhs.description
        }
    }

    private func countMarkdownFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" && isRegularFile($0) }
            .count
    }

    private func countRegularFiles(in directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return urls.filter(isRegularFile).count
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private enum ReloadMode {
        case initial
        case manualLint
        case afterFix
    }
}

struct OverviewMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let subtitle: String
}

struct VaultOverview {
    let totalPages: Int
    let totalSources: Int
    let sourcePages: Int
    let conceptPages: Int
    let entityPages: Int
    let domainPages: Int
    let synthesisPages: Int
    let latestMaintenance: Date?
    let latestCheck: Date?

    var metrics: [OverviewMetric] {
        [
            OverviewMetric(id: "pages", title: "Wiki 页面", value: "\(totalPages)", subtitle: "当前知识页总数"),
            OverviewMetric(id: "sources", title: "原始来源", value: "\(totalSources)", subtitle: "raw/sources 文件数"),
            OverviewMetric(id: "sourcePages", title: "来源页", value: "\(sourcePages)", subtitle: "wiki/sources"),
            OverviewMetric(id: "concepts", title: "概念页", value: "\(conceptPages)", subtitle: "wiki/concepts"),
            OverviewMetric(id: "entities", title: "实体页", value: "\(entityPages)", subtitle: "wiki/entities"),
            OverviewMetric(id: "domains", title: "领域页", value: "\(domainPages)", subtitle: "wiki/domains"),
            OverviewMetric(id: "synthesis", title: "综合页", value: "\(synthesisPages)", subtitle: "wiki/synthesis"),
            OverviewMetric(id: "maintenance", title: "最近维护", value: Self.displayDate(latestMaintenance), subtitle: "最近一次写入记录"),
            OverviewMetric(id: "lint", title: "最近检查", value: Self.displayDate(latestCheck), subtitle: "最近一次 health 检查"),
        ]
    }

    private static func displayDate(_ date: Date?) -> String {
        guard let date else { return "暂无" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct LintSummary {
    let scannedFiles: Int
    let totalIssues: Int
    let fixableIssues: Int
    let highPriorityIssues: Int
    let generatedAtText: String

    init(result: LintResultDTO) {
        scannedFiles = result.scannedFiles ?? 0
        totalIssues = result.issues.count
        fixableIssues = result.fixableIssueIds?.count ?? 0
        highPriorityIssues = result.issues.filter { $0.severity == "error" }.count
        generatedAtText = Self.displayDate(result.generatedAt)
    }

    private static func displayDate(_ value: String?) -> String {
        guard let value else { return "刚刚" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value)
            ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: value)
            }()

        guard let date else { return "刚刚" }

        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "MM-dd HH:mm"
        return display.string(from: date)
    }
}

struct HealthDimension: Identifiable {
    let id: String
    let title: String
    let issueCount: Int?
    let status: HealthDimensionStatus
    let subtitle: String

    static let placeholder: [HealthDimension] = [
        HealthDimension(id: "integrity", title: "结构完整性", issueCount: nil, status: .unknown, subtitle: "frontmatter、标题、重复"),
        HealthDimension(id: "links", title: "导航与链接", issueCount: nil, status: .unknown, subtitle: "断链、孤立页、索引"),
        HealthDimension(id: "freshness", title: "新鲜度", issueCount: nil, status: .unknown, subtitle: "过期待复查页面"),
        HealthDimension(id: "coverage", title: "覆盖度 / 缺口", issueCount: nil, status: .unknown, subtitle: "薄页、知识缺口"),
    ]

    static func fromLintResult(_ result: LintResultDTO) -> [HealthDimension] {
        let integrityCount = result.issues.filter {
            ["missing_frontmatter", "missing_heading", "duplicate_title"].contains($0.kind)
        }.count
        let linkCount = result.issues.filter {
            ["broken_link", "orphan_page", "missing_index_entry"].contains($0.kind)
        }.count
        let freshnessCount = result.issues.filter { $0.kind == "stale_page" }.count
        let coverageCount = result.issues.filter {
            ["thin_page", "knowledge_gap"].contains($0.kind)
        }.count

        return [
            HealthDimension(
                id: "integrity",
                title: "结构完整性",
                issueCount: integrityCount,
                status: .fromCount(integrityCount),
                subtitle: "frontmatter、标题、重复"
            ),
            HealthDimension(
                id: "links",
                title: "导航与链接",
                issueCount: linkCount,
                status: .fromCount(linkCount),
                subtitle: "断链、孤立页、索引"
            ),
            HealthDimension(
                id: "freshness",
                title: "新鲜度",
                issueCount: freshnessCount,
                status: .fromCount(freshnessCount),
                subtitle: "过期待复查页面"
            ),
            HealthDimension(
                id: "coverage",
                title: "覆盖度 / 缺口",
                issueCount: coverageCount,
                status: .fromCount(coverageCount),
                subtitle: "薄页、知识缺口"
            ),
        ]
    }
}

enum HealthDimensionStatus {
    case good
    case needsAttention
    case warning
    case unknown

    static func fromCount(_ count: Int) -> HealthDimensionStatus {
        switch count {
        case 0:
            .good
        case 1...2:
            .warning
        default:
            .needsAttention
        }
    }

    var title: String {
        switch self {
        case .good:
            "正常"
        case .warning:
            "留意"
        case .needsAttention:
            "需处理"
        case .unknown:
            "待检查"
        }
    }

    var color: Color {
        switch self {
        case .good:
            Theme.success
        case .warning:
            Theme.warning
        case .needsAttention:
            Theme.error
        case .unknown:
            Theme.textTertiary
        }
    }
}

enum IssueFilter: String, CaseIterable, Identifiable {
    case all
    case fixable
    case highPriority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部问题"
        case .fixable:
            "可修复"
        case .highPriority:
            "高优先级"
        }
    }
}

struct LintIssue: Identifiable {
    let id: String
    let description: String
    let severity: Severity
    let type: String
    let kindTitle: String
    let affectedPage: String?
    let fixable: Bool

    enum Severity: String {
        case high
        case medium
        case low

        var color: Color {
            switch self {
            case .high:
                Theme.error
            case .medium:
                Theme.warning
            case .low:
                Theme.textSecondary
            }
        }

        var title: String {
            switch self {
            case .high:
                "高"
            case .medium:
                "中"
            case .low:
                "低"
            }
        }

        var rank: Int {
            switch self {
            case .high:
                0
            case .medium:
                1
            case .low:
                2
            }
        }
    }

    init(dto: LintIssueDTO) {
        id = dto.id
        description = dto.message
        severity = switch dto.severity {
        case "error":
            .high
        case "warning":
            .medium
        default:
            .low
        }
        type = dto.kind
        kindTitle = Self.kindTitles[dto.kind] ?? dto.kind
        affectedPage = dto.path
        fixable = dto.fixable ?? false
    }

    private static let kindTitles: [String: String] = [
        "missing_frontmatter": "缺少 Frontmatter",
        "missing_heading": "缺少一级标题",
        "broken_link": "断裂链接",
        "orphan_page": "孤立页面",
        "missing_index_entry": "索引缺失",
        "duplicate_title": "标题重复",
        "stale_page": "页面过期",
        "thin_page": "内容偏薄",
        "knowledge_gap": "知识缺口",
    ]
}

struct IssueBreakdownItem: Identifiable {
    let id: String
    let title: String
    let count: Int

    static func fromIssues(_ issues: [LintIssue]) -> [IssueBreakdownItem] {
        let knownOrder = [
            "断裂链接",
            "孤立页面",
            "索引缺失",
            "标题重复",
            "页面过期",
            "内容偏薄",
            "知识缺口",
            "缺少 Frontmatter",
            "缺少一级标题",
        ]
        let grouped = Dictionary(grouping: issues, by: \.kindTitle)

        return knownOrder.compactMap { title in
            guard let values = grouped[title], !values.isEmpty else { return nil }
            return IssueBreakdownItem(id: title, title: title, count: values.count)
        }
    }
}

struct AffectedPageSummary: Identifiable {
    let id: String
    let path: String
    let issueCount: Int

    static func fromIssues(_ issues: [LintIssue]) -> [AffectedPageSummary] {
        let grouped = Dictionary(grouping: issues.compactMap(\.affectedPage), by: { $0 })
        return grouped
            .map { AffectedPageSummary(id: $0.key, path: $0.key, issueCount: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.issueCount != rhs.issueCount {
                    return lhs.issueCount > rhs.issueCount
                }
                return lhs.path < rhs.path
            }
    }
}
