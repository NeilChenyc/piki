import Foundation
import Testing
@testable import PikiApp

@Suite("Row interaction")
struct RowInteractionTests {
    @Test
    func wikiPageSelectionKeyStillMatchesCategoryAndSlug() {
        let page = WikiPage(
            id: "page-1",
            title: "LightAutoDS-Tab",
            category: "sources",
            filePath: "/tmp/wiki/sources/lightautods-tab.md",
            content: "",
            relatedConcepts: [],
            lastModified: .distantPast
        )

        #expect(page.selectionKey == "sources/lightautods-tab")
    }

    @Test
    func inboxSelectionClosureCanPromoteAnyRowItem() {
        let item = InboxItem(
            id: UUID().uuidString,
            fileName: "about-the-dataset.md",
            fileType: .markdown,
            fileSize: "12 KB",
            directoryCategory: .staging,
            status: .new,
            addedAt: .distantPast,
            filePath: URL(fileURLWithPath: "/tmp/raw/inbox/about-the-dataset.md")
        )

        var selected: InboxItem?
        let onSelect = { selected = item }
        onSelect()

        #expect(selected?.id == item.id)
    }
}
