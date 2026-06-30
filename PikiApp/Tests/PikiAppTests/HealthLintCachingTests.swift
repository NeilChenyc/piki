import Foundation
import Testing
@testable import PikiApp

private enum HealthTestError: Error {
    case unimplemented
}

@MainActor
@Suite("Health lint caching")
struct HealthLintCachingTests {
    @Test
    func healthViewModelDoesNotRunLintDuringInitialLoad() async {
        let runtime = HealthCachingRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeVault()

        let viewModel = HealthViewModel()
        await viewModel.loadIfNeeded(appState: appState)

        #expect(runtime.runLintCallCount == 0)
    }

    @Test
    func rerunLintUsesRuntimeServiceAndUpdatesCachedResult() async {
        let runtime = HealthCachingRuntimeService()
        runtime.stubbedLintResult = sampleLintResult()

        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeVault()

        let viewModel = HealthViewModel()
        await viewModel.loadIfNeeded(appState: appState)
        viewModel.rerunLint(appState: appState)

        await runtime.waitForRunLint()

        #expect(runtime.runLintCallCount == 1)
        #expect(appState.cachedLintResult?.result.generatedAt == "2026-06-23T12:00:00Z")
    }

    @Test
    func healthSummaryUsesThreeDimensionsWithoutCoverageCard() async {
        let runtime = HealthCachingRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeVault()
        appState.cacheLintResult(sampleLintResult(), receivedAt: Date())

        let viewModel = HealthViewModel()
        await viewModel.loadIfNeeded(appState: appState)

        #expect(viewModel.healthDimensions.count == 3)
        #expect(viewModel.healthDimensions.map(\.title) == ["结构完整性", "导航与链接", "复查状态"])
    }

    @Test
    func cachedLintResultPopulatesHealthSummary() async {
        let runtime = HealthCachingRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeVault()
        appState.cacheLintResult(sampleLintResult(), receivedAt: Date())

        let viewModel = HealthViewModel()
        await viewModel.loadIfNeeded(appState: appState)

        #expect(viewModel.lintSummary != nil)
        #expect(viewModel.lintIssues.count == 2)
        #expect(viewModel.issueBreakdown.isEmpty == false)
    }

    private func makeVault() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wiki = directory.appendingPathComponent("wiki/sources", isDirectory: true)
        let raw = directory.appendingPathComponent("raw/sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try? "# Test".write(to: wiki.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)
        try? "source".write(to: raw.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        return directory
    }

    private func sampleLintResult() -> LintResultDTO {
        LintResultDTO(
            generatedAt: "2026-06-23T12:00:00Z",
            scannedFiles: 12,
            issues: [
                LintIssueDTO(
                    id: "broken-1",
                    kind: "broken_link",
                    severity: "high",
                    path: "wiki/sources/test.md",
                    message: "Broken link found",
                    fixable: true
                ),
                LintIssueDTO(
                    id: "orphan-1",
                    kind: "orphan_page",
                    severity: "medium",
                    path: "wiki/concepts/orphan.md",
                    message: "Page has no inbound links",
                    fixable: false
                )
            ],
            issueCounts: [
                "broken_link": 1,
                "orphan_page": 1
            ],
            fixableIssueIds: ["broken-1"]
        )
    }
}

@MainActor
private final class HealthCachingRuntimeService: RuntimeServiceProtocol {
    private(set) var runLintCallCount = 0
    var stubbedLintResult: LintResultDTO?

    func health() async throws -> ServiceHealth { throw HealthTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw HealthTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw HealthTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw HealthTestError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw HealthTestError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw HealthTestError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw HealthTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw HealthTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw HealthTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func rollback(entryId: String) async throws {}
    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] { [] }
    func enqueueIngest(vaultPath: String, paths: [String]) async throws {}
    func processIngestQueue(vaultPath: String?) async throws {}
    func runLint(vaultPath: String) async throws -> LintResultDTO {
        runLintCallCount += 1
        guard let stubbedLintResult else { throw HealthTestError.unimplemented }
        return stubbedLintResult
    }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}

    func waitForRunLint() async {
        while runLintCallCount == 0 {
            await Task.yield()
        }
    }
}
