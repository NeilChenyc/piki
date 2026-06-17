import SwiftUI

struct MarkdownTextView: View {
    let content: String
    let foregroundColor: Color

    init(_ content: String, foregroundColor: Color = Theme.textPrimary) {
        self.content = content
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        if let attributed = markdownAttributedString {
            Text(attributed)
                .font(.system(size: 13))
                .foregroundStyle(foregroundColor)
                .textSelection(.enabled)
        } else {
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(foregroundColor)
                .textSelection(.enabled)
        }
    }

    private var markdownAttributedString: AttributedString? {
        var options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        options.allowsExtendedAttributes = true

        guard var result = try? AttributedString(
            markdown: content,
            options: options
        ) else {
            return nil
        }

        result.foregroundColor = foregroundColor
        result.font = .system(size: 13)

        for run in result.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                let range = run.range
                result[range].font = .system(size: 12, design: .monospaced)
                result[range].backgroundColor = Theme.cardBackground
            }
        }

        return result
    }
}
