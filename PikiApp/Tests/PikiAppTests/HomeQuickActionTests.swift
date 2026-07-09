import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Home quick actions")
struct HomeQuickActionTests {
    @Test
    func quickActionLabelsMatchPlannedChineseCopy() {
        #expect(QuickAction.uploadFile.title == "上传文件")
        #expect(QuickAction.ask.title == "提个问题")
        #expect(QuickAction.healthCheck.title == "运行健康检查")
    }

    @Test
    func healthCheckQuickActionPrefillsPromptWithoutSendingTask() {
        let runtime = HomeQuickActionRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeTemporaryDirectory()

        let viewModel = HomeViewModel()
        viewModel.handleQuickAction(.healthCheck)

        #expect(viewModel.inputText.contains("health"))
        #expect(viewModel.messages.isEmpty)
        #expect(runtime.createdRequests.isEmpty)
    }

    @Test
    func askQuickActionDoesNotMutateConversationState() {
        let viewModel = HomeViewModel()

        viewModel.handleQuickAction(.ask)

        #expect(viewModel.inputText.isEmpty)
        #expect(viewModel.messages.isEmpty)
    }

    @Test
    func podcastPromptGuidesUserToReplacePlaceholderLinkBeforeSending() {
        let viewModel = HomeViewModel()

        viewModel.preparePodcastPrompt()

        #expect(viewModel.inputText.contains("播客链接："))
        #expect(viewModel.inputText.contains("请把这里替换为单集链接后再发送"))
        #expect(viewModel.inputText.contains("先完成完整转录，再整理进知识库"))
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@MainActor
private final class HomeQuickActionRuntimeService: RuntimeServiceProtocol {
    private(set) var createdRequests: [TaskCreateRequest] = []

    func health() async throws -> ServiceHealth { throw HomeQuickActionTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw HomeQuickActionTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw HomeQuickActionTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw HomeQuickActionTestError.unimplemented }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        createdRequests.append(request)
        return TaskCreateResponse(taskId: "task-1", status: "running")
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO { throw HomeQuickActionTestError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw HomeQuickActionTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw HomeQuickActionTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw HomeQuickActionTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw HomeQuickActionTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}

private enum HomeQuickActionTestError: Error {
    case unimplemented
}
