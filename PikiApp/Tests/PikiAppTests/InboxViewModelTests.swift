import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Inbox view model")
struct InboxViewModelTests {
    @Test
    func loadVaultInboxExposesDirectoryAndTypeFilters() async throws {
        let vaultURL = makeTemporaryDirectory()
        try makeRawDirectoryStructure(in: vaultURL)

        let inboxFile = vaultURL.appendingPathComponent("raw/inbox/draft.md")
        let inboxTextFile = vaultURL.appendingPathComponent("raw/inbox/notes.txt")
        let sourceFile = vaultURL.appendingPathComponent("raw/sources/article.md")
        let assetPDF = vaultURL.appendingPathComponent("raw/assets/article/original.pdf")
        let assetDOCX = vaultURL.appendingPathComponent("raw/assets/brief/original.docx")

        try "# draft".write(to: inboxFile, atomically: true, encoding: .utf8)
        try "quick notes".write(to: inboxTextFile, atomically: true, encoding: .utf8)
        try "# source".write(to: sourceFile, atomically: true, encoding: .utf8)
        try Data("pdf".utf8).write(to: assetPDF)
        try Data("docx".utf8).write(to: assetDOCX)

        let viewModel = InboxViewModel()
        await viewModel.loadVaultInbox(vaultURL: vaultURL)

        #expect(viewModel.items.count == 5)
        #expect(viewModel.directoryCounts[.all] == 5)
        #expect(viewModel.directoryCounts[.staging] == 2)
        #expect(viewModel.directoryCounts[.source] == 1)
        #expect(viewModel.directoryCounts[.asset] == 2)

        #expect(viewModel.fileTypeCounts[.all] == 5)
        #expect(viewModel.fileTypeCounts[.markdown] == 2)
        #expect(viewModel.fileTypeCounts[.pdf] == 1)
        #expect(viewModel.fileTypeCounts[.docx] == 1)
        #expect(viewModel.fileTypeCounts[.text] == 1)
        #expect(viewModel.fileTypeCounts[.other] == 0)
        #expect(InboxDirectoryFilter.staging.title == "原资料")
    }

    @Test
    func filteredItemsCombineDirectoryAndTypeSelection() async throws {
        let vaultURL = makeTemporaryDirectory()
        try makeRawDirectoryStructure(in: vaultURL)

        try Data("pdf".utf8).write(to: vaultURL.appendingPathComponent("raw/assets/article/original.pdf"))
        try Data("docx".utf8).write(to: vaultURL.appendingPathComponent("raw/assets/brief/original.docx"))
        try "# source".write(to: vaultURL.appendingPathComponent("raw/sources/article.md"), atomically: true, encoding: .utf8)
        try "meeting notes".write(to: vaultURL.appendingPathComponent("raw/inbox/notes.txt"), atomically: true, encoding: .utf8)

        let viewModel = InboxViewModel()
        await viewModel.loadVaultInbox(vaultURL: vaultURL)

        viewModel.selectedDirectoryFilter = .asset
        viewModel.selectedFileTypeFilter = .pdf
        #expect(viewModel.filteredItems.count == 1)
        #expect(viewModel.filteredItems.first?.fileType == .pdf)
        #expect(viewModel.filteredItems.first?.directoryCategory == .asset)

        viewModel.selectedDirectoryFilter = .source
        viewModel.selectedFileTypeFilter = .markdown
        #expect(viewModel.filteredItems.count == 1)
        #expect(viewModel.filteredItems.first?.directoryCategory == .source)

        viewModel.selectedDirectoryFilter = .staging
        viewModel.selectedFileTypeFilter = .text
        #expect(viewModel.filteredItems.count == 1)
        #expect(viewModel.filteredItems.first?.fileType == .text)
        #expect(viewModel.filteredItems.first?.directoryCategory == .staging)
    }

    @Test
    func handleFileDropCopiesFileIntoRawInbox() async throws {
        let vaultURL = makeTemporaryDirectory()
        let appState = AppState(runtimeService: InboxStubRuntimeService())
        appState.vaultPath = vaultURL

        let externalDirectory = makeTemporaryDirectory()
        let sourceURL = externalDirectory.appendingPathComponent("note.md")
        try "# hello\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let viewModel = InboxViewModel()

        viewModel.handleFileDrop([sourceURL], appState: appState)

        let copiedURL = vaultURL.appendingPathComponent("raw/inbox/note.md")
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(try String(contentsOf: copiedURL, encoding: .utf8) == "# hello\n")
        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].filePath == copiedURL)
        #expect(viewModel.selectedItem?.filePath == copiedURL)
    }

    @Test
    func handleFileDropDeduplicatesNameWhenInboxFileExists() async throws {
        let vaultURL = makeTemporaryDirectory()
        let rawInboxURL = vaultURL.appendingPathComponent("raw/inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: rawInboxURL, withIntermediateDirectories: true)
        try "old".write(to: rawInboxURL.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let appState = AppState(runtimeService: InboxStubRuntimeService())
        appState.vaultPath = vaultURL

        let externalDirectory = makeTemporaryDirectory()
        let sourceURL = externalDirectory.appendingPathComponent("note.md")
        try "new".write(to: sourceURL, atomically: true, encoding: .utf8)

        let viewModel = InboxViewModel()

        viewModel.handleFileDrop([sourceURL], appState: appState)

        let copiedURL = rawInboxURL.appendingPathComponent("note-2.md")
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(try String(contentsOf: copiedURL, encoding: .utf8) == "new")
        #expect(viewModel.items[0].filePath == copiedURL)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRawDirectoryStructure(in vaultURL: URL) throws {
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent("raw/inbox", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent("raw/sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent("raw/assets/article", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent("raw/assets/brief", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}

@MainActor
private final class InboxStubRuntimeService: RuntimeServiceProtocol {
    func health() async throws -> ServiceHealth { throw InboxTestError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw InboxTestError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw InboxTestError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw InboxTestError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw InboxTestError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw InboxTestError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw InboxTestError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw InboxTestError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw InboxTestError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { throw InboxTestError.unimplemented }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw InboxTestError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws { throw InboxTestError.unimplemented }
}

private enum InboxTestError: Error {
    case unimplemented
}
