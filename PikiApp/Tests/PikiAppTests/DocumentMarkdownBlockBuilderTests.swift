import Foundation
import Testing
@testable import PikiApp

@Suite("Document markdown blocks")
struct DocumentMarkdownBlockBuilderTests {
    @MainActor
    @Test
    func buildsMetadataHeadingAndTableAsOrderedSegments() {
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

        let segments = DocumentMarkdownDebug.segments(
            for: source,
            mode: MarkdownDocumentPresentation.Mode.documentPage(
                displayTitle: "LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统"
            )
        )

        #expect(segments.count == 2)

        guard case .textCluster(let cluster) = segments[0].kind else {
            Issue.record("expected text cluster as first segment")
            return
        }
        #expect(cluster.attributedText.string.contains("type"))
        #expect(cluster.attributedText.string.contains("created"))
        #expect(cluster.attributedText.string.contains("LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统"))
        #expect(cluster.attributedText.string.contains("这是第一段。"))

        guard case .specialBlock(let specialBlock) = segments[1].kind else {
            Issue.record("expected special block as second segment")
            return
        }

        if case .table(let table) = specialBlock.kind {
            #expect(table.headers.count == 2)
            #expect(table.rows.count == 2)
        } else {
            Issue.record("expected table special block")
        }
    }

    @MainActor
    @Test
    func injectsDisplayTitleIntoLeadingTextClusterWhenBodyHasNoHeading() {
        let source = """
        ---
        title: 页面标题
        kind: memo
        ---

        第一段正文
        """

        let segments = DocumentMarkdownDebug.segments(
            for: source,
            mode: MarkdownDocumentPresentation.Mode.documentPage(displayTitle: "页面标题")
        )

        #expect(segments.count == 1)

        guard case .textCluster(let cluster) = segments[0].kind else {
            Issue.record("expected text cluster")
            return
        }
        #expect(cluster.attributedText.string.contains("kind"))
        #expect(cluster.attributedText.string.contains("页面标题"))
        #expect(cluster.attributedText.string.contains("第一段正文"))
    }

    @MainActor
    @Test
    func buildsBlockquoteAndDividerInsideTextClusterAndKeepsTableDedicated() {
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

        let segments = DocumentMarkdownDebug.segments(
            for: source,
            mode: MarkdownDocumentPresentation.Mode.documentPage(displayTitle: "测试页面")
        )

        #expect(segments.count == 3)

        guard case .textCluster(let leadingCluster) = segments[0].kind else {
            Issue.record("expected leading text cluster")
            return
        }
        #expect(leadingCluster.attributedText.string.contains("来源：arXiv 2507.13413v1"))

        guard case .specialBlock(let dividerBlock) = segments[1].kind else {
            Issue.record("expected divider special block")
            return
        }
        if case .divider = dividerBlock.kind {
            let matchedDivider = true
            #expect(matchedDivider)
        } else {
            Issue.record("expected divider special block")
        }

        guard case .specialBlock(let tableBlock) = segments[2].kind else {
            Issue.record("expected trailing table special block")
            return
        }
        if case .table(let table) = tableBlock.kind {
            #expect(table.headers.count == 2)
            #expect(table.rows.count == 1)
        } else {
            Issue.record("expected table special block")
        }
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
    func mergesAdjacentTextualDocumentBlocksIntoSingleCluster() {
        let segments = DocumentMarkdownDebug.segments(
            for: """
            ---
            title: 页面标题
            type: note
            ---

            # 页面标题

            第一段正文。

            - 列表项一
            - 列表项二

            > 一段引用

            ```swift
            print("hello")
            ```
            """,
            mode: .documentPage(displayTitle: "页面标题")
        )

        #expect(segments.count == 1)

        guard case .textCluster(let cluster) = segments[0].kind else {
            Issue.record("expected a single text cluster")
            return
        }

        #expect(cluster.attributedText.string.contains("页面标题"))
        #expect(cluster.attributedText.string.contains("第一段正文。"))
        #expect(cluster.attributedText.string.contains("列表项一"))
        #expect(cluster.attributedText.string.contains("一段引用"))
        #expect(cluster.attributedText.string.contains("print(\"hello\")"))
    }

    @MainActor
    @Test
    func tableBreaksDocumentIntoSeparateTextClusters() {
        let segments = DocumentMarkdownDebug.segments(
            for: """
            # 标题

            表格前正文。

            | 列一 | 列二 |
            | --- | --- |
            | A | B |

            表格后正文。
            """,
            mode: .plain
        )

        #expect(segments.count == 3)

        guard case .textCluster(let leadingCluster) = segments[0].kind else {
            Issue.record("expected first segment to be a text cluster")
            return
        }
        guard case .specialBlock(let specialBlock) = segments[1].kind else {
            Issue.record("expected second segment to be a special block")
            return
        }
        guard case .textCluster(let trailingCluster) = segments[2].kind else {
            Issue.record("expected third segment to be a text cluster")
            return
        }

        #expect(leadingCluster.attributedText.string.contains("表格前正文。"))
        #expect(trailingCluster.attributedText.string.contains("表格后正文。"))

        if case .table(let table) = specialBlock.kind {
            #expect(table.headers.count == 2)
            #expect(table.rows.count == 1)
        } else {
            Issue.record("expected special block to contain a table")
        }
    }
}
