import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Home display state")
struct HomeDisplayStateTests {
    @Test
    func emptyStateUsesHeroPlaceholderAndVaultHint() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.connectionStatus = .connected
        appState.vaultPath = nil

        let viewModel = HomeViewModel()
        let state = HomeViewDisplayState(appState: appState, viewModel: viewModel)

        #expect(state.isEmptyState)
        #expect(state.inputPlaceholder == "有问题尽管问")
        #expect(state.emptyStateHint == "请先在设置里选择一个 vault。")
        #expect(state.inputHint == "请先在设置里选择一个知识库。")
    }

    @Test
    func chatStateUsesDockedPlaceholderAfterFirstMessage() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.connectionStatus = .connected
        appState.vaultPath = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)
        appState.applyServiceHealth(
            ServiceHealth(
                ok: true,
                runnerAvailable: true,
                runnerDetail: "stub",
                provider: "stub",
                anthropicAPIKeyConfigured: true,
                anthropicBaseURL: nil,
                agentModel: "stub",
                agentRuntimeEnabled: true,
                agentRuntimeConfigured: true,
                claudeConfigDir: nil
            )
        )

        let viewModel = HomeViewModel()
        viewModel.messages = [
            ChatMessage(id: "1", role: .user, content: "hello", timestamp: .now)
        ]

        let state = HomeViewDisplayState(appState: appState, viewModel: viewModel)

        #expect(!state.isEmptyState)
        #expect(state.inputPlaceholder == "上传新知识或随意提问")
        #expect(state.inputHint == nil)
        #expect(state.emptyStateHint == nil)
    }

    @Test
    func pendingInputChangesEmptyStatePlaceholderFirst() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.connectionStatus = .connected
        appState.vaultPath = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)

        let viewModel = HomeViewModel()
        viewModel.pendingInputTaskId = "task-1"
        viewModel.pendingInputPrompt = "需要你补充更多信息"

        let state = HomeViewDisplayState(appState: appState, viewModel: viewModel)

        #expect(state.isEmptyState)
        #expect(state.inputPlaceholder == "继续这轮对话")
        #expect(state.emptyStateHint == "需要你补充更多信息")
        #expect(state.inputHint == "需要你补充更多信息")
    }

    @Test
    func runningConversationStatusEnablesAnimatedStatusText() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.connectionStatus = .connected
        appState.vaultPath = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)

        let viewModel = HomeViewModel()
        viewModel.isSending = true
        viewModel.statusText = "正在生成回答"

        let state = HomeViewDisplayState(appState: appState, viewModel: viewModel)

        #expect(state.shouldAnimateStatusText)
    }

    @Test
    func nonRunningStatusDoesNotAnimateStatusText() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.connectionStatus = .connected
        appState.vaultPath = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)

        let viewModel = HomeViewModel()
        viewModel.isSending = false
        viewModel.statusText = "已完成"

        let state = HomeViewDisplayState(appState: appState, viewModel: viewModel)

        #expect(!state.shouldAnimateStatusText)
    }

    @Test
    func unconfiguredRuntimeShowsOnboardingHintInsteadOfError() {
        let appState = AppState(runtimeService: HomeDisplayRuntimeService())
        appState.applyServiceHealth(
            ServiceHealth(
                ok: true,
                runnerAvailable: true,
                runnerDetail: "ready",
                provider: "claude",
                anthropicAPIKeyConfigured: false,
                anthropicBaseURL: nil,
                agentModel: nil,
                agentRuntimeEnabled: true,
                agentRuntimeConfigured: false,
                claudeConfigDir: nil
            )
        )
        appState.vaultPath = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)

        let state = HomeViewDisplayState(appState: appState, viewModel: HomeViewModel())

        #expect(state.emptyStateHint == "本地 Runtime 已就绪，请前往设置填写模型、Base URL 和 API Key。")
        #expect(state.inputHint == "本地 Runtime 已就绪，请前往设置填写模型、Base URL 和 API Key。")
    }
}

private enum HomeDisplayStateTestError: Error {
    case unimplemented
}

private final class HomeDisplayRuntimeService: RuntimeServiceProtocol {
    func health() async throws -> ServiceHealth { throw HomeDisplayStateTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw HomeDisplayStateTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw HomeDisplayStateTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw HomeDisplayStateTestError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw HomeDisplayStateTestError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw HomeDisplayStateTestError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw HomeDisplayStateTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw HomeDisplayStateTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw HomeDisplayStateTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw HomeDisplayStateTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}
