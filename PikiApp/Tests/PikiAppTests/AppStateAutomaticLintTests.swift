import Foundation
import Testing
@testable import PikiApp

private enum AppStateAutomaticLintError: Error {
    case unimplemented
}

@MainActor
@Suite("AppState automatic lint")
struct AppStateAutomaticLintTests {
    @Test
    func automaticLintRunsOnceWhenConnectedAndVaultExists() async {
        let runtime = AutomaticLintRuntimeService()
        runtime.stubbedLintResult = sampleLintResult()

        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeVault()

        await appState.prewarmHealthLintIfNeeded()
        await appState.prewarmHealthLintIfNeeded()

        #expect(runtime.runLintCallCount == 1)
        #expect(appState.cachedLintResult?.result.generatedAt == sampleLintResult().generatedAt)
    }

    @Test
    func automaticLintSkipsWhenDisconnected() async {
        let runtime = AutomaticLintRuntimeService()
        runtime.stubbedLintResult = sampleLintResult()

        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .disconnected
        appState.vaultPath = makeVault()

        await appState.prewarmHealthLintIfNeeded()

        #expect(runtime.runLintCallCount == 0)
        #expect(appState.cachedLintResult == nil)
    }

    @Test
    func automaticLintSkipsWithoutVault() async {
        let runtime = AutomaticLintRuntimeService()
        runtime.stubbedLintResult = sampleLintResult()

        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = nil

        await appState.prewarmHealthLintIfNeeded()

        #expect(runtime.runLintCallCount == 0)
        #expect(appState.cachedLintResult == nil)
    }

    private func makeVault() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wiki = directory.appendingPathComponent("wiki", isDirectory: true)
        let raw = directory.appendingPathComponent("raw/sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        return directory
    }

    private func sampleLintResult() -> LintResultDTO {
        LintResultDTO(
            generatedAt: "2026-06-30T12:00:00Z",
            scannedFiles: 6,
            issues: [
                LintIssueDTO(
                    id: "stale-1",
                    kind: "stale_page",
                    severity: "warning",
                    path: "wiki/concepts/test.md",
                    message: "Page needs review",
                    fixable: false
                )
            ],
            issueCounts: ["stale_page": 1],
            fixableIssueIds: []
        )
    }
}

@MainActor
private final class AutomaticLintRuntimeService: RuntimeServiceProtocol {
    private(set) var runLintCallCount = 0
    var stubbedLintResult: LintResultDTO?

    func health() async throws -> ServiceHealth { throw AppStateAutomaticLintError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw AppStateAutomaticLintError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw AppStateAutomaticLintError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw AppStateAutomaticLintError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw AppStateAutomaticLintError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw AppStateAutomaticLintError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw AppStateAutomaticLintError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw AppStateAutomaticLintError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw AppStateAutomaticLintError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO {
        runLintCallCount += 1
        guard let stubbedLintResult else { throw AppStateAutomaticLintError.unimplemented }
        return stubbedLintResult
    }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}
