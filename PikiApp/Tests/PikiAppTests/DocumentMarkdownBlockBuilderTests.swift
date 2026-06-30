import AppKit
import Foundation
import Testing
@testable import PikiApp

@Suite("Document markdown blocks")
struct DocumentMarkdownBlockBuilderTests {
    @MainActor
    @Test
    func buildsSingleRenderedDocumentForMetadataHeadingAndTable() {
        let source = """
        ---
        title: LightAutoDS-Tab
        type: wiki-source
        created: 2026-06-17
        ---

        # LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统

        这是第一段。

        | Agent | 职责 |
        | --- | --- |
        | Planner | 制定 ML pipeline |
        | Generator | 生成代码 |
        """

        let document = DocumentMarkdownDebug.renderedDocument(
            for: source,
            mode: .documentPage(
                displayTitle: "LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统"
            )
        )

        #expect(document.attributedText.string.contains("type"))
        #expect(document.attributedText.string.contains("created"))
        #expect(document.attributedText.string.contains("LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统"))
        #expect(document.attributedText.string.contains("这是第一段。"))
        #expect(document.tableCount == 1)
        #expect(document.imageAttachmentCount == 0)

        let fullRange = NSRange(location: 0, length: document.attributedText.length)
        var paragraphStyles: [NSParagraphStyle] = []
        document.attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, _, _ in
            if let paragraphStyle = value as? NSParagraphStyle {
                paragraphStyles.append(paragraphStyle)
            }
        }
        #expect(paragraphStyles.contains { !$0.textBlocks.isEmpty })
    }

    @MainActor
    @Test
    func injectsDisplayTitleIntoUnifiedDocumentWhenBodyHasNoHeading() {
        let source = """
        ---
        title: 页面标题
        kind: memo
        ---

        第一段正文
        """

        let document = DocumentMarkdownDebug.renderedDocument(
            for: source,
            mode: .documentPage(displayTitle: "页面标题")
        )

        #expect(document.attributedText.string.contains("kind"))
        #expect(document.attributedText.string.contains("页面标题"))
        #expect(document.attributedText.string.contains("第一段正文"))
        #expect(document.tableCount == 0)
    }

    @MainActor
    @Test
    func keepsBlockquoteDividerAndTableInsideSameRenderedDocument() {
        let source = """
        ---
        title: 测试页面
        type: wiki-source
        ---

        # 测试页面

        > 来源：arXiv 2507.13413v1

        ---

        | Agent | 职责 |
        | --- | --- |
        | Planner | 制定方案 |
        """

        let document = DocumentMarkdownDebug.renderedDocument(
            for: source,
            mode: .documentPage(displayTitle: "测试页面")
        )

        #expect(document.attributedText.string.contains("来源：arXiv 2507.13413v1"))
        #expect(document.attributedText.string.contains("Agent"))
        #expect(document.attributedText.string.contains("Planner"))
        #expect(document.tableCount == 1)
    }

    @MainActor
    @Test
    func documentViewAcceptsPreviewScaleInput() {
        let view = DocumentMarkdownView(
            "# Title\n\nBody",
            presentationMode: .documentPage(displayTitle: "Title"),
            textScale: 1.3
        )

        #expect(view.textScale == 1.3)
    }

    @MainActor
    @Test
    func preservesListItemParagraphSpacingWithinSingleListItem() {
        let items = MessageMarkdownDebug.listItemTexts(
            for: """
            - 第一段

              第二段
            """
        )

        #expect(items.count == 1)
        #expect(items.first == "第一段\n\n第二段")
    }

    @MainActor
    @Test
    func mergesTextTableAndTrailingParagraphIntoOneRenderedDocument() {
        let document = DocumentMarkdownDebug.renderedDocument(
            for: """
            # 标题

            第一段正文。

            - 列表项一
            - 列表项二

            > 一段引用

            ```swift
            print("hello")
            ```

            | 列一 | 列二 |
            | --- | --- |
            | A | B |

            表格后正文。
            """,
            mode: .plain
        )

        #expect(document.attributedText.string.contains("标题"))
        #expect(document.attributedText.string.contains("第一段正文。"))
        #expect(document.attributedText.string.contains("列表项一"))
        #expect(document.attributedText.string.contains("一段引用"))
        #expect(document.attributedText.string.contains("print(\"hello\")"))
        #expect(document.attributedText.string.contains("列一"))
        #expect(document.attributedText.string.contains("表格后正文。"))
        #expect(document.tableCount == 1)
    }

    @MainActor
    @Test
    func rendersMarkdownImagesAsInlineAttachmentsInsideUnifiedDocument() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let imageURL = temporaryDirectory.appendingPathComponent("markdown-render-image-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()
        try? image.tiffRepresentation?.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let document = DocumentMarkdownDebug.renderedDocument(
            for: "![示意图](\(imageURL.path(percentEncoded: false)))",
            mode: .plain,
            baseURL: temporaryDirectory
        )

        #expect(document.imageAttachmentCount == 1)
    }

    @MainActor
    @Test
    func tableParagraphStylesOnlyContainTableCellBlocks() {
        let document = DocumentMarkdownDebug.renderedDocument(
            for: """
            | Name | Role |
            | --- | --- |
            | Piki | Assistant |
            """,
            mode: .plain
        )

        let fullRange = NSRange(location: 0, length: document.attributedText.length)
        var foundTableParagraph = false

        document.attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, _, _ in
            guard let paragraphStyle = value as? NSParagraphStyle, !paragraphStyle.textBlocks.isEmpty else {
                return
            }

            foundTableParagraph = true
            #expect(paragraphStyle.textBlocks.count == 1)
            #expect(paragraphStyle.textBlocks.first is NSTextTableBlock)
            #expect((paragraphStyle.textBlocks.first is NSTextTable) == false)
        }

        #expect(foundTableParagraph)
    }
}
