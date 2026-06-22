import AppKit
import Foundation
import SwiftUI

struct MarkdownInlineTextStyler {
    static func makeAttributedString(
        from source: String,
        font: Font,
        foregroundColor: Color,
        linkColor: Color = Color(nsColor: .linkColor)
    ) throws -> AttributedString {
        let rewritten = WikiLinkParser.rewriteMarkdownPreservingWikiLinks(source)

        var options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        options.allowsExtendedAttributes = true

        var attributed = try AttributedString(markdown: rewritten, options: options)
        let runs = Array(attributed.runs)

        for run in runs {
            attributed[run.range].font = font
            attributed[run.range].foregroundColor = run.link == nil ? foregroundColor : linkColor

            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .system(size: 12, design: .monospaced)
                attributed[run.range].backgroundColor = Theme.surfaceSecondary
                attributed[run.range].foregroundColor = Theme.textPrimary
            }
        }

        return attributed
    }

    static func makeNSAttributedString(
        from source: String,
        font: Font,
        foregroundColor: Color,
        linkColor: NSColor = .linkColor
    ) throws -> NSAttributedString {
        let attributed = try makeAttributedString(
            from: source,
            font: font,
            foregroundColor: foregroundColor,
            linkColor: Color(nsColor: linkColor)
        )
        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            mutable.addAttributes([
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ], range: range)
        }

        return mutable
    }
}
