import Foundation
import AppKit
import Testing
@testable import PikiApp

@MainActor
@Suite("Inspiration panel")
struct InspirationViewModelTests {
    @Test
    func homeSplitGivesCollapsedSidebarSpaceToChatPane() {
        let defaultPaneWidths = HomeSplitMetrics.paneWidths(for: 1_046)
        let compactPaneWidths = HomeSplitMetrics.paneWidths(for: 700)

        #expect(defaultPaneWidths.chat == 654)
        #expect(defaultPaneWidths.inspiration == 392)
        #expect(compactPaneWidths.chat == 420)
        #expect(compactPaneWidths.inspiration == 280)
    }

    @Test
    func loadUsesSearchQueryAndStoresReverseChronologicalItems() async throws {
        let runtime = InspirationRuntimeService()
        runtime.listResponse = [
            makeInspiration(id: "insp_old", content: "old", createdAt: "2026-07-05T10:00:00+00:00"),
            makeInspiration(id: "insp_new", content: "new harness", createdAt: "2026-07-07T10:00:00+00:00")
        ]
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()
        viewModel.searchQuery = "harness"

        await viewModel.load(appState: appState)

        #expect(runtime.listRequests == [InspirationRuntimeService.ListRequest(vaultPath: "/tmp/piki-vault", query: "harness")])
        #expect(viewModel.items.map(\.id) == ["insp_new", "insp_old"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func submitDraftCreatesMemoAndClearsComposer() async throws {
        let runtime = InspirationRuntimeService()
        runtime.createdResponse = makeInspiration(id: "insp_created", content: "新的想法")
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()
        viewModel.draftText = " 新的想法 "

        await viewModel.submitDraft(appState: appState)

        #expect(runtime.createRequests.map(\.content) == ["新的想法"])
        #expect(viewModel.draftText.isEmpty)
        #expect(viewModel.items.map(\.id) == ["insp_created"])
    }

    @Test
    func doubleClickEditFlowUpdatesMemoInline() async throws {
        let runtime = InspirationRuntimeService()
        let original = makeInspiration(id: "insp_edit", content: "原始想法")
        runtime.updatedResponse = makeInspiration(id: "insp_edit", content: "更新想法")
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()
        viewModel.items = [original]

        viewModel.beginEditing(original)
        viewModel.editingText = "更新想法"
        await viewModel.saveEditing(appState: appState)

        #expect(runtime.updateRequests.map(\.id) == ["insp_edit"])
        #expect(runtime.updateRequests.map(\.request.content) == ["更新想法"])
        #expect(viewModel.editingId == nil)
        #expect(viewModel.items.first?.content == "更新想法")
    }

    @Test
    func deleteRemovesMemoFromListAfterRuntimeDelete() async throws {
        let runtime = InspirationRuntimeService()
        let memo = makeInspiration(id: "insp_delete", content: "要删除的想法")
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()
        viewModel.items = [memo]

        await viewModel.deleteInspiration(memo, appState: appState)

        #expect(runtime.deleteRequests.count == 1)
        #expect(runtime.deleteRequests.first?.id == "insp_delete")
        #expect(runtime.deleteRequests.first?.vaultPath == "/tmp/piki-vault")
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.statusMessage == "已删除")
    }

    @Test
    func pastedDraftImageUploadsAndAddsAttachmentPreview() async throws {
        let runtime = InspirationRuntimeService()
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        await viewModel.addDraftPastedImage(image, appState: appState)

        #expect(runtime.uploadedFiles.count == 1)
        #expect(runtime.uploadedFiles.first?.pathExtension == "png")
        #expect(viewModel.draftAttachments.count == 1)
        #expect(viewModel.draftAttachments.first?.mimeType == "image/png")
        #expect(viewModel.draftAttachments.first?.bufferedPath == "/tmp/piki-staging/pasted.png")
    }

    @Test
    func pasteboardImageReaderLoadsHTMLDataURLImage() throws {
        let imageData = try makePNGData()
        let html = """
        <html><body><img src="data:image/png;base64,\(imageData.base64EncodedString())"></body></html>
        """
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("piki-inspiration-html-image-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)

        let images = InspirationPasteboardImageReader.images(from: pasteboard)

        #expect(images.count == 1)
        #expect(images.first?.size.width == 4)
        #expect(images.first?.size.height == 4)
    }

    @Test
    func returnKeyPolicySubmitsOnBareReturnAndKeepsShiftReturnForNewLine() {
        #expect(InspirationEditorKeyPolicy.returnAction(for: []) == .submit)
        #expect(InspirationEditorKeyPolicy.returnAction(for: [.shift]) == .insertNewline)
        #expect(InspirationEditorKeyPolicy.returnAction(for: [.command]) == .submit)
    }

    @Test
    func failedCompileStatusShowsFailedBadgePresentation() {
        let presentation = InspirationStatusPresentation.make(for: "failed")

        #expect(presentation.label == "整理失败")
        #expect(presentation.tone == .failed)
    }

    @Test
    func loadIfNeededDoesNotCompileInspirations() async throws {
        let runtime = InspirationRuntimeService()
        runtime.listResponse = [makeInspiration(id: "insp_pending", content: "待整理想法")]
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()

        await viewModel.loadIfNeeded(appState: appState)

        #expect(runtime.compileRequests.isEmpty)
        #expect(viewModel.items.map(\.id) == ["insp_pending"])
    }

    @Test
    func manualUpdateWikiStartsCompileRequest() async throws {
        let runtime = InspirationRuntimeService()
        runtime.compileResponse = InspirationCompileResponse(
            compiledCount: 1,
            taskId: nil,
            sourcePath: "raw/sources/inspirations.md",
            error: nil
        )
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()

        await viewModel.updateWiki(appState: appState)

        #expect(runtime.compileRequests == ["/tmp/piki-vault"])
        #expect(viewModel.statusMessage == "随手记已更新到 Wiki")
    }

    @Test
    func manualUpdateWikiReloadsAfterReturnedTaskCompletes() async throws {
        let runtime = InspirationRuntimeService()
        runtime.compileResponse = InspirationCompileResponse(
            compiledCount: 1,
            taskId: "task-1",
            sourcePath: "raw/sources/inspirations.md",
            error: nil
        )
        runtime.taskResponses["task-1"] = TaskRecordDTO(
            id: "task-1",
            status: "completed",
            summary: "done",
            output: .init(answer: nil, summary: "done", lintResult: nil, sessionId: nil, pendingInput: nil)
        )
        runtime.listResponse = [
            makeInspiration(
                id: "insp_compiled",
                content: "已整理想法",
                compileStatus: "compiled",
                compiledHash: "sha256:insp_compiled"
            )
        ]
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()

        await viewModel.updateWiki(appState: appState)

        #expect(runtime.compileRequests == ["/tmp/piki-vault"])
        #expect(runtime.getTaskRequests == ["task-1"])
        #expect(runtime.listRequests == [InspirationRuntimeService.ListRequest(vaultPath: "/tmp/piki-vault", query: nil)])
        #expect(viewModel.items.map(\.id) == ["insp_compiled"])
        #expect(viewModel.statusMessage == "随手记已更新到 Wiki")
    }

    @Test
    func manualUpdateWikiShowsNoChangesMessage() async throws {
        let runtime = InspirationRuntimeService()
        runtime.compileResponse = InspirationCompileResponse(
            compiledCount: 0,
            taskId: nil,
            sourcePath: nil,
            error: nil
        )
        let appState = makeAppState(runtime: runtime)
        let viewModel = InspirationViewModel()

        await viewModel.updateWiki(appState: appState)

        #expect(runtime.compileRequests == ["/tmp/piki-vault"])
        #expect(viewModel.statusMessage == "没有需要更新的随手记")
    }

    private func makeAppState(runtime: InspirationRuntimeService) -> AppState {
        let appState = AppState(runtimeService: runtime)
        appState.connectionStatus = .connected
        appState.vaultPath = URL(fileURLWithPath: "/tmp/piki-vault", isDirectory: true)
        return appState
    }

    private func makeInspiration(
        id: String,
        content: String,
        createdAt: String = "2026-07-07T10:00:00+00:00",
        compileStatus: String = "pending",
        compiledHash: String? = nil
    ) -> InspirationDTO {
        InspirationDTO(
            id: id,
            path: "raw/inspirations/2026-07/\(id).md",
            content: content,
            attachments: [],
            createdAt: createdAt,
            updatedAt: createdAt,
            contentHash: "sha256:\(id)",
            compileStatus: compileStatus,
            compileTaskId: nil,
            compiledHash: compiledHash,
            sourcePath: nil
        )
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class InspirationRuntimeService: RuntimeServiceProtocol {
    struct ListRequest: Equatable {
        let vaultPath: String
        let query: String?
    }

    struct UpdateRequest {
        let id: String
        let request: InspirationUpdateRequest
    }

    var listResponse: [InspirationDTO] = []
    var createdResponse: InspirationDTO?
    var updatedResponse: InspirationDTO?
    var listRequests: [ListRequest] = []
    var createRequests: [InspirationCreateRequest] = []
    var updateRequests: [UpdateRequest] = []
    var compileRequests: [String] = []
    var compileResponse = InspirationCompileResponse(
        compiledCount: 1,
        taskId: "task-1",
        sourcePath: "raw/sources/inspirations.md",
        error: nil
    )
    var getTaskRequests: [String] = []
    var taskResponses: [String: TaskRecordDTO] = [:]
    var deleteRequests: [(id: String, vaultPath: String)] = []
    var uploadedFiles: [URL] = []

    func health() async throws -> ServiceHealth { throw InspirationTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw InspirationTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        throw InspirationTestError.unimplemented
    }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw InspirationTestError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw InspirationTestError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func getTask(taskId: String) async throws -> TaskRecordDTO {
        getTaskRequests.append(taskId)
        guard let response = taskResponses[taskId] else {
            throw InspirationTestError.unimplemented
        }
        return response
    }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw InspirationTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw InspirationTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        uploadedFiles.append(fileURL)
        return BufferedUploadResponse(
            filename: "pasted.png",
            bufferedPath: "/tmp/piki-staging/pasted.png",
            sizeBytes: 128,
            originalPath: fileURL.path(percentEncoded: false)
        )
    }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw InspirationTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}

    func listInspirations(vaultPath: String, query: String?) async throws -> [InspirationDTO] {
        listRequests.append(ListRequest(vaultPath: vaultPath, query: query))
        return listResponse
    }

    func createInspiration(_ request: InspirationCreateRequest) async throws -> InspirationDTO {
        createRequests.append(request)
        return createdResponse ?? InspirationDTO(
            id: "insp_default",
            path: "raw/inspirations/2026-07/insp_default.md",
            content: request.content,
            attachments: request.attachments,
            createdAt: "2026-07-07T10:00:00+00:00",
            updatedAt: "2026-07-07T10:00:00+00:00",
            contentHash: "sha256:default",
            compileStatus: "pending",
            compileTaskId: nil,
            compiledHash: nil,
            sourcePath: nil
        )
    }

    func updateInspiration(id: String, request: InspirationUpdateRequest) async throws -> InspirationDTO {
        updateRequests.append(UpdateRequest(id: id, request: request))
        return updatedResponse ?? InspirationDTO(
            id: id,
            path: "raw/inspirations/2026-07/\(id).md",
            content: request.content,
            attachments: request.attachments,
            createdAt: "2026-07-07T10:00:00+00:00",
            updatedAt: "2026-07-07T10:01:00+00:00",
            contentHash: "sha256:updated",
            compileStatus: "pending",
            compileTaskId: nil,
            compiledHash: nil,
            sourcePath: nil
        )
    }

    func compileInspirations(vaultPath: String) async throws -> InspirationCompileResponse {
        compileRequests.append(vaultPath)
        return compileResponse
    }

    func deleteInspiration(id: String, vaultPath: String) async throws {
        deleteRequests.append((id: id, vaultPath: vaultPath))
    }
}

private enum InspirationTestError: Error {
    case unimplemented
}
