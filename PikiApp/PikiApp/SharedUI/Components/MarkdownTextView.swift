import AppKit
import Markdown
import SwiftUI

struct MarkdownTextView: View {
    let content: String
    let foregroundColor: Color
    let baseURL: URL?

    private var blocks: [RenderedMarkdownBlock] {
        MarkdownDocumentRenderer.parse(content, baseURL: baseURL)
    }

    init(_ content: String, foregroundColor: Color = Theme.textPrimary, baseURL: URL? = nil) {
        self.content = content
        self.foregroundColor = foregroundColor
        self.baseURL = baseURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, foregroundColor: foregroundColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct MarkdownBlockView: View {
    let block: RenderedMarkdownBlock
    let foregroundColor: Color

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(text, font: headingFont(level), foregroundColor: foregroundColor)
                .padding(.top, level <= 2 ? 8 : 4)
                .padding(.bottom, 2)

        case .paragraph(let text):
            InlineMarkdownText(text, font: .system(size: 13), foregroundColor: foregroundColor)

        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.border)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, nestedBlock in
                        MarkdownBlockView(block: nestedBlock, foregroundColor: Theme.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(for: item)
                        InlineMarkdownText(item.text, font: .system(size: 13), foregroundColor: foregroundColor)
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let table):
            MarkdownTableView(table: table)

        case .thematicBreak:
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.vertical, 8)

        case .html(let html):
            CodeBlockView(language: "html", code: html)

        case .image(let image):
            MarkdownImageView(image: image)
        }
    }

    @ViewBuilder
    private func listMarker(for item: MarkdownListItem) -> some View {
        if let checkbox = item.checkbox {
            SwiftUI.Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(checkbox == .checked ? Theme.success : Theme.textTertiary)
                .frame(width: 18, alignment: .trailing)
        } else {
            SwiftUI.Text(item.marker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: item.isOrdered ? 28 : 16, alignment: .trailing)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 22, weight: .bold)
        case 2: .system(size: 18, weight: .semibold)
        case 3: .system(size: 15, weight: .semibold)
        default: .system(size: 13, weight: .semibold)
        }
    }
}

private struct InlineMarkdownText: View {
    let source: String
    let font: Font
    let foregroundColor: Color

    init(_ source: String, font: Font, foregroundColor: Color) {
        self.source = source
        self.font = font
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        if let attributed {
            SwiftUI.Text(attributed)
                .lineSpacing(3)
        } else {
            SwiftUI.Text(source)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineSpacing(3)
        }
    }

    private var attributed: AttributedString? {
        var options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        options.allowsExtendedAttributes = true

        guard var result = try? AttributedString(markdown: source, options: options) else {
            return nil
        }

        result.font = font
        result.foregroundColor = foregroundColor

        for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].font = .system(size: 12, design: .monospaced)
            result[run.range].backgroundColor = Theme.surfaceSecondary
            result[run.range].foregroundColor = Theme.textPrimary
        }

        return result
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                SwiftUI.Text(language.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                SwiftUI.Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 0.7)
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        tableCell(table.headers[column], isHeader: true)
                    }
                }

                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            let value = column < table.rows[rowIndex].count ? table.rows[rowIndex][column] : ""
                            tableCell(value, isHeader: false)
                        }
                    }
                }
            }
            .background(Theme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 0.7)
            )
            .clipShape(.rect(cornerRadius: 8))
        }
    }

    private func tableCell(_ value: String, isHeader: Bool) -> some View {
        InlineMarkdownText(
            value,
            font: .system(size: 12, weight: isHeader ? .semibold : .regular),
            foregroundColor: isHeader ? Theme.textPrimary : Theme.textSecondary
        )
        .frame(minWidth: 110, maxWidth: 240, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHeader ? Theme.surfaceSecondary : Theme.cardBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 0.7)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.7)
        }
    }
}

private struct MarkdownImageView: View {
    let image: MarkdownImage

    var body: some View {
        if let url = image.resolvedURL {
            if url.isFileURL, let nsImage = NSImage(contentsOf: url) {
                renderedImage(Image(nsImage: nsImage))
            } else if !url.isFileURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let loadedImage):
                        renderedImage(loadedImage)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private func renderedImage(_ image: SwiftUI.Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 0.7)
            )
            .accessibilityLabel(self.image.alt.isEmpty ? "Markdown image" : self.image.alt)
    }

    private var placeholder: some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "photo")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                SwiftUI.Text(image.alt.isEmpty ? "Image" : image.alt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                if !image.source.isEmpty {
                    SwiftUI.Text(image.source)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 0.7)
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}

private enum RenderedMarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockquote([RenderedMarkdownBlock])
    case list([MarkdownListItem])
    case codeBlock(language: String?, code: String)
    case table(MarkdownTable)
    case thematicBreak
    case html(String)
    case image(MarkdownImage)
}

private struct MarkdownListItem: Identifiable {
    enum Checkbox {
        case checked
        case unchecked
    }

    let id = UUID()
    let level: Int
    let marker: String
    let isOrdered: Bool
    let checkbox: Checkbox?
    let text: String
}

private struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]
}

private struct MarkdownImage {
    let alt: String
    let source: String
    let resolvedURL: URL?
}

private enum MarkdownDocumentRenderer {
    static func parse(_ source: String, baseURL: URL?) -> [RenderedMarkdownBlock] {
        let document = Document(parsing: source)
        let renderedBlocks = document.children.flatMap { blocks(from: $0, level: 0, baseURL: baseURL) }
        return renderedBlocks.isEmpty ? fallbackParse(source) : renderedBlocks
    }

    private static func blocks(from markup: Markup, level: Int, baseURL: URL?) -> [RenderedMarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(level: heading.level, text: heading.plainText)]

        case let paragraph as Paragraph:
            if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Markdown.Image {
                return [.image(imageModel(from: image, baseURL: baseURL))]
            }
            return [.paragraph(inlineMarkdown(from: paragraph))]

        case let blockquote as BlockQuote:
            let nested = blockquote.children.flatMap { blocks(from: $0, level: level, baseURL: baseURL) }
            return [.blockquote(nested.isEmpty ? [.paragraph(blockquote.format().trimmedMarkdown)] : nested)]

        case let orderedList as OrderedList:
            return [.list(listItems(from: orderedList, level: level, ordered: true, startIndex: Int(orderedList.startIndex)))]

        case let unorderedList as UnorderedList:
            return [.list(listItems(from: unorderedList, level: level, ordered: false, startIndex: 1))]

        case let codeBlock as CodeBlock:
            return [.codeBlock(language: codeBlock.language, code: codeBlock.code)]

        case let table as Markdown.Table:
            return [.table(tableModel(from: table))]

        case is ThematicBreak:
            return [.thematicBreak]

        case let html as HTMLBlock:
            return [.html(html.rawHTML)]

        default:
            let formatted = markup.format().trimmedMarkdown
            return formatted.isEmpty ? [] : [.paragraph(formatted)]
        }
    }

    private static func listItems(
        from list: Markup,
        level: Int,
        ordered: Bool,
        startIndex: Int
    ) -> [MarkdownListItem] {
        var result: [MarkdownListItem] = []

        for (offset, child) in list.children.enumerated() {
            guard let item = child as? ListItem else { continue }

            let text = item.children
                .filter { !($0 is OrderedList) && !($0 is UnorderedList) }
                .map(inlineTextForListItemBlock)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            result.append(
                MarkdownListItem(
                    level: level,
                    marker: ordered ? "\(startIndex + offset)." : "•",
                    isOrdered: ordered,
                    checkbox: checkbox(from: item.checkbox),
                    text: text
                )
            )

            for nested in item.children {
                if let orderedList = nested as? OrderedList {
                    result.append(contentsOf: listItems(from: orderedList, level: level + 1, ordered: true, startIndex: Int(orderedList.startIndex)))
                } else if let unorderedList = nested as? UnorderedList {
                    result.append(contentsOf: listItems(from: unorderedList, level: level + 1, ordered: false, startIndex: 1))
                }
            }
        }

        return result
    }

    private static func checkbox(from checkbox: Markdown.Checkbox?) -> MarkdownListItem.Checkbox? {
        switch checkbox {
        case .checked:
            return .checked
        case .unchecked:
            return .unchecked
        case nil:
            return nil
        }
    }

    private static func tableModel(from table: Markdown.Table) -> MarkdownTable {
        let headers = table.head.children.map(inlineMarkdown(from:))
        let rows = table.body.children.map { row in
            row.children.map(inlineMarkdown(from:))
        }
        return MarkdownTable(headers: headers, rows: rows)
    }

    private static func imageModel(from image: Markdown.Image, baseURL: URL?) -> MarkdownImage {
        let source = image.source?.trimmedMarkdown ?? ""
        return MarkdownImage(
            alt: image.plainText,
            source: source,
            resolvedURL: resolveImageURL(source: source, baseURL: baseURL)
        )
    }

    private static func resolveImageURL(source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty else { return nil }

        if let url = URL(string: source), url.scheme != nil {
            return url
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        return baseURL?.appendingPathComponent(source)
    }

    private static func inlineMarkdown(from markup: Markup) -> String {
        let inlineText = markup.children
            .map { $0.format().trimmedMarkdown }
            .joined()
            .trimmedMarkdown

        if !inlineText.isEmpty {
            return inlineText
        }

        if let plain = markup as? PlainTextConvertibleMarkup {
            return plain.plainText.trimmedMarkdown
        }

        return markup.format().trimmedMarkdown
    }

    private static func inlineTextForListItemBlock(_ markup: Markup) -> String {
        if markup is Paragraph || markup is Heading || markup is Markdown.Table.Cell {
            return inlineMarkdown(from: markup)
        }
        return markup.format().trimmedMarkdown
    }

    private static func fallbackParse(_ source: String) -> [RenderedMarkdownBlock] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [.paragraph(trimmed)]
    }
}

private extension String {
    var trimmedMarkdown: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
