import Foundation
import SwiftUI
import Testing
@testable import PikiApp

@Suite("Markdown inline text styling")
struct MarkdownInlineTextStylerTests {
    @Test
    func buildsStandardLinkAttributesForWikiLinks() throws {
        let attributed = try MarkdownInlineTextStyler.makeAttributedString(
            from: "前文 [[concepts/长期记忆|长期记忆]] 后文",
            font: .system(size: 13),
            foregroundColor: Theme.textPrimary
        )

        let linkRuns = attributed.runs.compactMap { run in
            run.link
        }

        #expect(linkRuns.count == 1)
        #expect(linkRuns.first?.absoluteString.contains("piki-wiki://open") == true)
        #expect(attributed.characters.contains("长"))
    }
}
