import Foundation
import Testing
@testable import PikiApp

@Suite("Markdown document presentation")
struct MarkdownDocumentPresentationTests {
    @Test
    func documentModeMovesFrontmatterToMetadataAndKeepsBodyHeadingAsSingleDocumentTitle() {
        let source = """
        ---
        title: Kimi K2 Thinking 英文专业媒体评价
        type: source
        tags: [Kimi, Moonshot, LLM]
        raw_source: raw/sources/kimi-de6329c5.md
        ---

        # Kimi K2 Thinking 英文专业媒体评价

        这个来源说了什么

        本文由传媒撰写。
        """

        let document = MarkdownDocumentPresentation.prepare(
            source: source,
            mode: .documentPage(displayTitle: "Kimi K2 Thinking 英文专业媒体评价")
        )

        #expect(document.bodyMarkdown == """
        # Kimi K2 Thinking 英文专业媒体评价

        这个来源说了什么

        本文由传媒撰写。
        """)
        #expect(document.metadata.map { $0.key } == ["type", "tags", "raw_source"])
        #expect(document.metadata.map { $0.value } == ["source", "[Kimi, Moonshot, LLM]", "raw/sources/kimi-de6329c5.md"])
        #expect(document.resolvedDisplayTitle == "Kimi K2 Thinking 英文专业媒体评价")
        #expect(document.shouldRenderTitleInsideDocument == false)
    }

    @Test
    func documentModeLeavesBodyHeadingWhenItDiffersFromDisplayedTitle() {
        let source = """
        ---
        title: 页面标题
        type: note
        ---

        # 正文里的小节标题

        内容。
        """

        let document = MarkdownDocumentPresentation.prepare(
            source: source,
            mode: .documentPage(displayTitle: "页面标题")
        )

        #expect(document.bodyMarkdown == """
        # 正文里的小节标题

        内容。
        """)
        #expect(document.metadata.map { $0.key } == ["type"])
        #expect(document.resolvedDisplayTitle == "页面标题")
        #expect(document.shouldRenderTitleInsideDocument == false)
    }

    @Test
    func plainModePreservesFrontmatterAndHeading() {
        let source = """
        ---
        title: 页面标题
        ---

        # 页面标题
        """

        let document = MarkdownDocumentPresentation.prepare(source: source, mode: .plain)

        #expect(document.bodyMarkdown == source)
        #expect(document.metadata.isEmpty)
        #expect(document.resolvedDisplayTitle == nil)
        #expect(document.shouldRenderTitleInsideDocument == false)
    }

    @Test
    func documentModeUsesFrontmatterTitleWhenDisplayTitleIsNil() {
        let source = """
        ---
        title: 页面标题
        type: source
        ---

        # 页面标题

        正文内容
        """

        let document = MarkdownDocumentPresentation.prepare(
            source: source,
            mode: .documentPage(displayTitle: nil)
        )

        #expect(document.bodyMarkdown == """
        # 页面标题

        正文内容
        """)
        #expect(document.metadata.map { $0.key } == ["type"])
        #expect(document.resolvedDisplayTitle == "页面标题")
        #expect(document.shouldRenderTitleInsideDocument == false)
    }

    @Test
    func documentModeInjectsDisplayTitleWhenBodyHasNoHeading() {
        let source = """
        ---
        title: 页面标题
        kind: memo
        ---

        第一段正文
        """

        let document = MarkdownDocumentPresentation.prepare(
            source: source,
            mode: .documentPage(displayTitle: "页面标题")
        )

        #expect(document.bodyMarkdown == "第一段正文")
        #expect(document.metadata.map { $0.key } == ["kind"])
        #expect(document.resolvedDisplayTitle == "页面标题")
        #expect(document.shouldRenderTitleInsideDocument)
    }
}
