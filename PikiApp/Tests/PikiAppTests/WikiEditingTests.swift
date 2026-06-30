import Foundation
import Testing
@testable import PikiApp

@Suite("Wiki editing")
struct WikiEditingTests {
    @MainActor
    @Test
    func enterEditRestoresUnsavedDraftForPage() throws {
        let viewModel = WikiViewModel()
        let page = WikiPage(
            id: "/tmp/wiki/sources/test.md",
            title: "Test",
            category: "sources",
            filePath: "/tmp/wiki/sources/test.md",
            content: "# Test\n\nSaved",
            relatedConcepts: [],
            lastModified: .distantPast
        )

        viewModel.categories = [
            WikiCategory(id: "sources", title: "Sources", icon: "doc.text", pages: [page])
        ]
        viewModel.selectedPage = page

        viewModel.startEditingSelectedPage()
        #expect(viewModel.isEditingSelectedPage)
        #expect(viewModel.editingText == "# Test\n\nSaved")

        viewModel.updateDraftForSelectedPage("# Test\n\nDraft")
        #expect(viewModel.selectedPageHasUnsavedDraft)

        viewModel.stopEditingSelectedPagePreservingDraft()
        #expect(!viewModel.isEditingSelectedPage)

        viewModel.startEditingSelectedPage()
        #expect(viewModel.isEditingSelectedPage)
        #expect(viewModel.editingText == "# Test\n\nDraft")
    }

    @MainActor
    @Test
    func cancelEditingDiscardsDraftAndRestoresSavedContent() {
        let viewModel = WikiViewModel()
        let page = WikiPage(
            id: "/tmp/wiki/sources/test.md",
            title: "Test",
            category: "sources",
            filePath: "/tmp/wiki/sources/test.md",
            content: "# Test\n\nSaved",
            relatedConcepts: [],
            lastModified: .distantPast
        )

        viewModel.categories = [
            WikiCategory(id: "sources", title: "Sources", icon: "doc.text", pages: [page])
        ]
        viewModel.selectedPage = page

        viewModel.startEditingSelectedPage()
        viewModel.updateDraftForSelectedPage("# Test\n\nDraft")
        viewModel.cancelEditingSelectedPage()

        #expect(!viewModel.isEditingSelectedPage)
        #expect(!viewModel.selectedPageHasUnsavedDraft)
        #expect(viewModel.editingText == nil)
        #expect(viewModel.selectedPage?.content == "# Test\n\nSaved")
    }

    @MainActor
    @Test
    func saveEditingWritesFileAndRefreshesTitleAndLinks() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("sources/test.md")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Old\n\nBody".write(to: fileURL, atomically: true, encoding: .utf8)

        let page = WikiPage(
            id: fileURL.path(percentEncoded: false),
            title: "Old",
            category: "sources",
            filePath: fileURL.path(percentEncoded: false),
            content: "# Old\n\nBody",
            relatedConcepts: [],
            lastModified: .distantPast
        )

        let viewModel = WikiViewModel()
        viewModel.categories = [
            WikiCategory(id: "sources", title: "Sources", icon: "doc.text", pages: [page])
        ]
        viewModel.selectedPage = page

        viewModel.startEditingSelectedPage()
        viewModel.updateDraftForSelectedPage("""
        ---
        title: Fresh Title
        ---

        # Fresh Title

        Linked to [[concepts/长期记忆]]
        """)

        try viewModel.saveEditingSelectedPage()

        let diskContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(diskContent.contains("Fresh Title"))
        #expect(!viewModel.isEditingSelectedPage)
        #expect(!viewModel.selectedPageHasUnsavedDraft)
        #expect(viewModel.selectedPage?.title == "Fresh Title")
        #expect(viewModel.selectedPage?.relatedConcepts.map(\.rawTarget) == ["concepts/长期记忆"])
        #expect(viewModel.selectedPage?.content == diskContent)
    }

    @MainActor
    @Test
    func previewScaleClampsToConfiguredRange() {
        let viewModel = WikiViewModel()

        #expect(viewModel.previewTextScale == 1.0)

        for _ in 0..<10 {
            viewModel.increasePreviewTextScale()
        }
        #expect(viewModel.previewTextScale == 1.3)
        #expect(!viewModel.canIncreasePreviewTextScale)

        for _ in 0..<10 {
            viewModel.decreasePreviewTextScale()
        }
        #expect(viewModel.previewTextScale == 0.85)
        #expect(!viewModel.canDecreasePreviewTextScale)
    }

    @MainActor
    @Test
    func refreshReloadsUpdatedFileContentAndRebindsSelection() async throws {
        let vaultURL = try makeWikiVault()
        let pageURL = vaultURL.appendingPathComponent("wiki/sources/test.md")
        try "# Original\n\nBefore".write(to: pageURL, atomically: true, encoding: .utf8)

        let viewModel = WikiViewModel()
        await viewModel.loadIfNeeded(vaultURL: vaultURL)

        let originalSelection = try #require(viewModel.selectedPage)
        #expect(originalSelection.content.contains("Before"))

        try "# Updated\n\nAfter".write(to: pageURL, atomically: true, encoding: .utf8)

        await viewModel.refreshWiki(vaultURL: vaultURL)

        let refreshedSelection = try #require(viewModel.selectedPage)
        #expect(refreshedSelection.id == originalSelection.id)
        #expect(refreshedSelection.title == "Updated")
        #expect(refreshedSelection.content.contains("After"))
        #expect(refreshedSelection.content != originalSelection.content)
    }

    @MainActor
    @Test
    func refreshFallsBackWhenSelectedPageWasDeleted() async throws {
        let vaultURL = try makeWikiVault()
        let deletedURL = vaultURL.appendingPathComponent("wiki/sources/delete-me.md")
        let survivorURL = vaultURL.appendingPathComponent("wiki/sources/keep-me.md")
        try "# Delete Me\n\nBody".write(to: deletedURL, atomically: true, encoding: .utf8)

        let viewModel = WikiViewModel()
        await viewModel.loadIfNeeded(vaultURL: vaultURL)
        let deletedPage = try #require(viewModel.selectedPage)
        #expect(URL(fileURLWithPath: deletedPage.filePath).lastPathComponent == deletedURL.lastPathComponent)

        try "# Keep Me\n\nBody".write(to: survivorURL, atomically: true, encoding: .utf8)

        try FileManager.default.removeItem(at: deletedURL)

        await viewModel.refreshWiki(vaultURL: vaultURL)

        let refreshedSelection = try #require(viewModel.selectedPage)
        #expect(URL(fileURLWithPath: refreshedSelection.filePath).lastPathComponent == survivorURL.lastPathComponent)
        #expect(!viewModel.categories.flatMap(\.pages).contains(where: {
            URL(fileURLWithPath: $0.filePath).lastPathComponent == deletedURL.lastPathComponent
        }))
    }

    @MainActor
    @Test
    func autoRefreshSkipsWhenSelectedPageHasUnsavedDraft() async throws {
        let vaultURL = try makeWikiVault()
        let pageURL = vaultURL.appendingPathComponent("wiki/sources/test.md")
        try "# Original\n\nBefore".write(to: pageURL, atomically: true, encoding: .utf8)

        let viewModel = WikiViewModel()
        await viewModel.loadIfNeeded(vaultURL: vaultURL)
        viewModel.startEditingSelectedPage()
        viewModel.updateDraftForSelectedPage("# Draft\n\nUnsaved")

        try "# Updated\n\nAfter".write(to: pageURL, atomically: true, encoding: .utf8)

        await viewModel.refreshWikiIfSafe(vaultURL: vaultURL)

        let selectedPage = try #require(viewModel.selectedPage)
        #expect(selectedPage.content.contains("Before"))
        #expect(viewModel.selectedPageHasUnsavedDraft)
        #expect(viewModel.editingText == "# Draft\n\nUnsaved")
    }

    @MainActor
    @Test
    func manualRefreshStillReloadsWhileDraftExists() async throws {
        let vaultURL = try makeWikiVault()
        let pageURL = vaultURL.appendingPathComponent("wiki/sources/test.md")
        try "# Original\n\nBefore".write(to: pageURL, atomically: true, encoding: .utf8)

        let viewModel = WikiViewModel()
        await viewModel.loadIfNeeded(vaultURL: vaultURL)
        viewModel.startEditingSelectedPage()
        viewModel.updateDraftForSelectedPage("# Draft\n\nUnsaved")

        try "# Updated\n\nAfter".write(to: pageURL, atomically: true, encoding: .utf8)

        await viewModel.refreshWiki(vaultURL: vaultURL)

        let selectedPage = try #require(viewModel.selectedPage)
        #expect(selectedPage.content.contains("After"))
        #expect(viewModel.selectedPageHasUnsavedDraft)
        #expect(viewModel.editingText == "# Draft\n\nUnsaved")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeWikiVault() throws -> URL {
        let directory = try makeTemporaryDirectory()
        let wikiURL = directory.appendingPathComponent("wiki", isDirectory: true)
        for category in WikiCategory.defaults.map(\.id) {
            try FileManager.default.createDirectory(
                at: wikiURL.appendingPathComponent(category, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return directory
    }
}
