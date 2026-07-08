import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Home trace state")
struct HomeTraceStateTests {
    @Test
    func sendMessageStartsAgentRunCollapsed() async throws {
        let runtime = HomeTraceRuntimeService()
        runtime.taskRecord = TaskRecordDTO(
            id: "task-1",
            status: "completed",
            summary: "done",
            output: .init(answer: "final answer", summary: "done", lintResult: nil, sessionId: nil, pendingInput: nil)
        )
        let appState = configuredAppState(runtime: runtime)
        let viewModel = HomeViewModel()

        viewModel.sendMessage("hello", appState: appState)

        await Task.yield()

        #expect(viewModel.messages.count == 2)
        let assistant = try #require(viewModel.messages.last)
        #expect(assistant.role == .assistant)
        #expect(assistant.isAgentRun)
        #expect(!assistant.isTraceExpanded)
    }

    @Test
    func stopCurrentTaskKeepsTraceCollapsedAfterFallbackStop() async throws {
        let runtime = HomeTraceRuntimeService()
        let appState = configuredAppState(runtime: runtime)
        let viewModel = HomeViewModel()

        viewModel.sendMessage("hello", appState: appState)
        await Task.yield()

        runtime.blockEvents = true

        viewModel.stopCurrentTask(appState: appState)
        await Task.yield()
        await Task.yield()

        let assistant = try #require(viewModel.messages.last)
        #expect(!assistant.isRunning)
        #expect(assistant.runStatus == "cancelled")
        #expect(!assistant.isTraceExpanded)
    }

    @Test
    func traceDeltaCreatesReasoningTraceItemForRunningAssistantMessage() async throws {
        let runtime = HomeTraceRuntimeService()
        let appState = configuredAppState(runtime: runtime)
        let viewModel = HomeViewModel()

        viewModel.sendMessage("hello", appState: appState)
        await Task.yield()

        let assistant = try #require(viewModel.messages.last)
        let event = try JSONDecoder().decode(
            TaskEvent.self,
            from: Data(
                """
                {
                  "id": "evt-1",
                  "task_id": "task-1",
                  "type": "agent.trace.delta",
                  "payload": {
                    "delta": "先读取 inbox 文件，再补充上下文。"
                  }
                }
                """.utf8
            )
        )

        _ = viewModel.handleForTesting(event, assistantMessageId: assistant.id)

        let updatedAssistant = try #require(viewModel.messages.last)
        let reasoning = try #require(updatedAssistant.traceItems.first(where: { $0.key == "reasoning" }))
        #expect(reasoning.summary == "先读取 inbox 文件，再补充上下文。")
        #expect(reasoning.category == "model")
        #expect(reasoning.status == "running")
    }

    @Test
    func structuredTaskFailureUsesFriendlyMessageAndAction() async throws {
        let runtime = HomeTraceRuntimeService()
        let appState = configuredAppState(runtime: runtime)
        let viewModel = HomeViewModel()

        viewModel.sendMessage("请播客转录", appState: appState)
        await Task.yield()

        let assistant = try #require(viewModel.messages.last)
        let event = try JSONDecoder().decode(
            TaskEvent.self,
            from: Data(
                """
                {
                  "id": "evt-structured-error",
                  "task_id": "task-1",
                  "type": "task.failed",
                  "payload": {
                    "error": "AccessKey ID 不存在或不属于当前阿里云账号。",
                    "error_code": "podcast.tingwu.invalid_access_key",
                    "error_title": "阿里云 AccessKey 无效",
                    "error_message": "AccessKey ID 不存在或不属于当前阿里云账号。",
                    "recovery_suggestion": "请在设置页检查 AccessKey ID 是否复制完整，且没有误填为 AppKey。",
                    "retryable": false,
                    "action_label": "打开播客转录设置",
                    "action_target": "settings.tingwu"
                  }
                }
                """.utf8
            )
        )

        _ = viewModel.handleForTesting(event, assistantMessageId: assistant.id)

        let updatedAssistant = try #require(viewModel.messages.last)
        #expect(updatedAssistant.runStatus == "failed")
        #expect(updatedAssistant.content.contains("阿里云 AccessKey 无效"))
        #expect(updatedAssistant.content.contains("AccessKey ID 不存在或不属于当前阿里云账号。"))
        #expect(updatedAssistant.content.contains("Traceback") == false)
        #expect(updatedAssistant.errorAction?.label == "打开播客转录设置")
        #expect(updatedAssistant.errorAction?.target == "settings.tingwu")
    }
}

@MainActor
private func configuredAppState(runtime: RuntimeServiceProtocol) -> AppState {
    let appState = AppState(runtimeService: runtime)
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
    return appState
}

private enum HomeTraceTestError: Error {
    case unimplemented
}

@MainActor
private final class HomeTraceRuntimeService: RuntimeServiceProtocol {
    var blockEvents = false
    var taskRecord = TaskRecordDTO(
        id: "task-1",
        status: "completed",
        summary: "done",
        output: .init(answer: "final answer", summary: "done", lintResult: nil, sessionId: nil, pendingInput: nil)
    )

    func health() async throws -> ServiceHealth { throw HomeTraceTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw HomeTraceTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw HomeTraceTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw HomeTraceTestError.unimplemented }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        TaskCreateResponse(taskId: taskRecord.id, status: "running")
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            if blockEvents {
                return
            }
            continuation.finish()
        }
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO { taskRecord }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { taskRecord }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { taskRecord }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw HomeTraceTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func rollback(entryId: String) async throws {}
    func listIngestQueue(status: String?) async throws -> [IngestQueueItemDTO] { [] }
    func enqueueIngest(vaultPath: String, paths: [String]) async throws {}
    func processIngestQueue(vaultPath: String?) async throws {}
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw HomeTraceTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}
