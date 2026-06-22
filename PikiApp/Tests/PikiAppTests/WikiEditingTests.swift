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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
