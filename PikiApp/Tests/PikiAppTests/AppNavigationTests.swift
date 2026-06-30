import SwiftUI
import Testing
@testable import PikiApp

@MainActor
@Suite("App navigation")
struct AppNavigationTests {
    @Test
    func sidebarTabTitlesUseChineseLabelsWhileKeepingWiki() {
        #expect(SidebarTab.home.title == "首页")
        #expect(SidebarTab.inbox.title == "资料箱")
        #expect(SidebarTab.wiki.title == "Wiki")
        #expect(SidebarTab.health.title == "知识库健康")
        #expect(SidebarTab.settings.title == "设置")
    }

    @Test
    func appStateDefaultsToVisibleSidebar() {
        let appState = AppState(runtimeService: NavigationStubRuntimeService())

        #expect(appState.sidebarVisibility == .all)
    }

    @Test
    func sidebarGreetingUsesWarmWelcomeCopy() {
        #expect(SidebarGreetingContent.title == "Hi")
        #expect(SidebarGreetingContent.message == "今天收获了什么？")
    }
}

@MainActor
private final class NavigationStubRuntimeService: RuntimeServiceProtocol {
    func health() async throws -> ServiceHealth { throw NavigationTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw NavigationTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw NavigationTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw NavigationTestError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw NavigationTestError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw NavigationTestError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw NavigationTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw NavigationTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw NavigationTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func rollback(entryId: String) async throws {}
    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] { [] }
    func enqueueIngest(vaultPath: String, paths: [String]) async throws {}
    func processIngestQueue(vaultPath: String?) async throws {}
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw NavigationTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}

private enum NavigationTestError: Error {
    case unimplemented
}
