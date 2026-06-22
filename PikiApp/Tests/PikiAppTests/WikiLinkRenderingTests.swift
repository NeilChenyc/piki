import Foundation
import Testing
@testable import PikiApp

@Suite("Wiki link rendering")
struct WikiLinkRenderingTests {
    @Test
    func parsesWikilinksIntoInlineSegments() {
        let segments = WikiLinkParser.parseInlineSegments(
            "Prefix [[concepts/长期记忆]] middle [[domains/知识管理|知识管理域]] suffix"
        )

        #expect(segments.count == 5)
        #expect(segments[0] == .markdown("Prefix "))
        #expect(segments[1] == .wikiLink(WikiLinkTarget(rawTarget: "concepts/长期记忆", category: .concepts, slug: "长期记忆", displayTitle: "长期记忆")))
        #expect(segments[2] == .markdown(" middle "))
        #expect(segments[3] == .wikiLink(WikiLinkTarget(rawTarget: "domains/知识管理", category: .domains, slug: "知识管理", displayTitle: "知识管理域")))
        #expect(segments[4] == .markdown(" suffix"))
    }

    @Test
    func extractsUniqueWikilinkTargetsFromMarkdown() {
        let links = WikiLinkParser.extractUniqueTargets(
            from: """
            - [[concepts/长期记忆]]
            - [[concepts/长期记忆]]
            - [[entities/Obsidian]]
            """
        )

        #expect(links.map(\.rawTarget) == ["concepts/长期记忆", "entities/Obsidian"])
    }

    @MainActor
    @Test
    func selectsPageForMatchingWikilinkPath() {
        let page = WikiPage(
            id: "1",
            title: "长期记忆",
            category: "concepts",
            filePath: "/tmp/wiki/concepts/长期记忆.md",
            content: "",
            relatedConcepts: [],
            lastModified: .distantPast
        )
        let viewModel = WikiViewModel()
        viewModel.categories = [
            WikiCategory(id: "concepts", title: "Concepts", icon: "lightbulb", pages: [page])
        ]

        let didSelect = viewModel.selectPage(for: WikiLinkTarget(
            rawTarget: "concepts/长期记忆",
            category: .concepts,
            slug: "长期记忆",
            displayTitle: "长期记忆"
        ))

        #expect(didSelect)
        #expect(viewModel.selectedPage?.id == page.id)
    }
}
