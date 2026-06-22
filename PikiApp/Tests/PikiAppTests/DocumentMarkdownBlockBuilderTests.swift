import Foundation
import Testing
@testable import PikiApp

@Suite("Document markdown blocks")
struct DocumentMarkdownBlockBuilderTests {
    @MainActor
    @Test
    func buildsMetadataHeadingAndTableAsSeparateBlocks() {
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

        let blocks = DocumentMarkdownDebug.blocks(
            for: source,
            mode: .documentPage(displayTitle: "LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统")
        )

        #expect(blocks.count >= 4)

        guard case .metadata(let metadata) = blocks[0].kind else {
            Issue.record("expected metadata as first block")
            return
        }
        #expect(metadata.map(\.key) == ["type", "created"])

        guard case .heading(let heading) = blocks[1].kind else {
            Issue.record("expected heading as second block")
            return
        }
        #expect(heading.level == 1)
        #expect(heading.text == "LightAutoDS-Tab: 面向表格数据的多 AutoML 智能体系统")

        #expect(
            blocks.contains { block in
                if case .table(let table) = block.kind {
                    return table.headers.count == 2 && table.rows.count == 2
                }
                return false
            }
        )
    }

    @MainActor
    @Test
    func injectsDisplayTitleAsHeadingBlockWhenBodyHasNoHeading() {
        let source = """
        ---
        title: 页面标题
        kind: memo
        ---

        第一段正文
        """

        let blocks = DocumentMarkdownDebug.blocks(
            for: source,
            mode: .documentPage(displayTitle: "页面标题")
        )

        #expect(blocks.count >= 3)

        guard case .metadata = blocks[0].kind else {
            Issue.record("expected metadata block first")
            return
        }
        guard case .heading(let heading) = blocks[1].kind else {
            Issue.record("expected injected heading block second")
            return
        }
        #expect(heading.text == "页面标题")
    }

    @MainActor
    @Test
    func buildsBlockquoteDividerAndTableAsDedicatedBlocks() {
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

        let blocks = DocumentMarkdownDebug.blocks(
            for: source,
            mode: .documentPage(displayTitle: "测试页面")
        )

        #expect(
            blocks.contains { block in
                if case .text(let payload) = block.kind {
                    return payload.style == .blockquote
                }
                return false
            }
        )

        #expect(
            blocks.contains { block in
                if case .divider = block.kind {
                    return true
                }
                return false
            }
        )

        #expect(
            blocks.contains { block in
                if case .table(let table) = block.kind {
                    return table.headers.count == 2 && table.rows.count == 1
                }
                return false
            }
        )
    }
}
