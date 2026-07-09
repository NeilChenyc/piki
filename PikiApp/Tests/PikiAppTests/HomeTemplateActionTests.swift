import Foundation
import Testing
@testable import PikiApp

private enum LocalTestError: Error {
    case unimplemented
}

@MainActor
@Suite("Home template actions")
struct HomeTemplateActionTests {
    @Test
    func inboxIngestTemplateSwitchesHomeAndSendsAttachedFile() async throws {
        let runtime = HomeTemplateRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeTemporaryDirectory()
        appState.selectedTab = .inbox

        let fileURL = appState.vaultPath!
            .appendingPathComponent("raw/inbox/test.md")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = HomeViewModel()
        viewModel.submitTemplateAction(
            .inboxIngest(fileURL: fileURL, fileName: "test.md"),
            appState: appState
        )

        await runtime.waitForCreateTask()

        #expect(appState.selectedTab == .home)
        #expect(runtime.uploadedFiles == [fileURL])
        #expect(runtime.createdRequests.count == 1)
        #expect(runtime.createdRequests[0].selectedPaths == ["/buffered/test.md"])
        #expect(runtime.createdRequests[0].userInput.contains("请帮我 ingest 这个文件"))
        #expect(viewModel.messages.contains(where: { $0.role == .user }))
    }

    @Test
    func lintTemplateSwitchesHomeAndRequestsLintWithoutAttachments() async throws {
        let runtime = HomeTemplateRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeTemporaryDirectory()
        appState.selectedTab = .health

        let viewModel = HomeViewModel()
        viewModel.submitTemplateAction(.runLintAndFix, appState: appState)

        await runtime.waitForCreateTask()

        #expect(appState.selectedTab == .home)
        #expect(runtime.uploadedFiles.isEmpty)
        #expect(runtime.createdRequests.count == 1)
        #expect(runtime.createdRequests[0].selectedPaths.isEmpty)
        #expect(runtime.createdRequests[0].userInput.contains("运行 lint"))
        #expect(runtime.createdRequests[0].userInput.contains("低风险问题"))
    }

    @Test
    func podcastKeywordRoutesToPodcastTranscriptionActionWithoutUrl() async throws {
        let runtime = HomeTemplateRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeTemporaryDirectory()

        let viewModel = HomeViewModel()
        viewModel.sendMessage(
            "我想上传一集播客并自动转录。请按播客转录流程先完成完整转录，再整理进知识库。",
            appState: appState
        )

        await runtime.waitForCreateTask()

        #expect(runtime.createdRequests.count == 1)
        #expect(runtime.createdRequests[0].actionContext["action"] == "podcast_transcribe")
        #expect(runtime.createdRequests[0].actionContext["podcast_url"] == nil)
    }

    @Test
    func templateActionRefusesToStartWhenBusy() {
        let runtime = HomeTemplateRuntimeService()
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = makeTemporaryDirectory()
        appState.selectedTab = .health

        let viewModel = HomeViewModel()
        viewModel.isSending = true

        viewModel.submitTemplateAction(.runLintAndFix, appState: appState)

        #expect(appState.selectedTab == .home)
        #expect(runtime.createdRequests.isEmpty)
        #expect(viewModel.messages.last?.role == .system)
        #expect(viewModel.messages.last?.content.contains("当前已有进行中的任务") == true)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@MainActor
private final class HomeTemplateRuntimeService: RuntimeServiceProtocol {
    private(set) var createdRequests: [TaskCreateRequest] = []
    private(set) var uploadedFiles: [URL] = []

    func health() async throws -> ServiceHealth {
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
    }

    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw LocalTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw LocalTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw LocalTestError.unimplemented }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        createdRequests.append(request)
        return TaskCreateResponse(taskId: "task-1", status: "running")
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        TaskRecordDTO(
            id: taskId,
            status: "completed",
            summary: "done",
            output: .init(answer: "done", summary: "done", lintResult: nil, sessionId: nil, pendingInput: nil)
        )
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw LocalTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw LocalTestError.unimplemented }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        uploadedFiles.append(fileURL)
        return BufferedUploadResponse(
            filename: fileURL.lastPathComponent,
            bufferedPath: "/buffered/\(fileURL.lastPathComponent)",
            sizeBytes: 5,
            originalPath: fileURL.path(percentEncoded: false)
        )
    }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw LocalTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}

    func waitForCreateTask() async {
        while createdRequests.isEmpty {
            await Task.yield()
        }
    }
}
