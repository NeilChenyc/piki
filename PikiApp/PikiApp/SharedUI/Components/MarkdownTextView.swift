import AppKit
import Markdown
import SwiftUI

struct DocumentMarkdownView: View {
    let presentationMode: MarkdownDocumentPresentation.Mode
    let content: String
    let baseURL: URL?
    let textScale: CGFloat
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?
    @State private var availableWidth: CGFloat? = nil

    private var preparedDocument: MarkdownDocumentPresentation.PreparedDocument {
        MarkdownDocumentPresentation.prepare(source: content, mode: presentationMode)
    }

    init(
        _ content: String,
        presentationMode: MarkdownDocumentPresentation.Mode = .plain,
        baseURL: URL? = nil,
        textScale: CGFloat = 1.0,
        onOpenWikiLink: ((WikiLinkTarget) -> Void)? = nil
    ) {
        self.content = content
        self.presentationMode = presentationMode
        self.baseURL = baseURL
        self.textScale = textScale
        self.onOpenWikiLink = onOpenWikiLink
    }

    var body: some View {
        let style = DocumentMarkdownStyle(scale: textScale)
        let renderedDocument = UnifiedMarkdownDocumentBuilder.makeDocument(
            preparedDocument: preparedDocument,
            baseURL: baseURL,
            configuration: .document(style: style)
        )

        MarkdownSelectableTextView(
            attributedText: renderedDocument.attributedText,
            layoutWidth: availableWidth,
            onOpenWikiLink: onOpenWikiLink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarkdownLayoutWidthReader())
        .onPreferenceChange(MarkdownLayoutWidthPreferenceKey.self) { width in
            guard width > 1, availableWidth != width else { return }
            availableWidth = width
        }
    }
}

struct MessageMarkdownView: View {
    let content: String
    let foregroundColor: Color
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    init(
        _ content: String,
        foregroundColor: Color = Theme.textPrimary,
        onOpenWikiLink: ((WikiLinkTarget) -> Void)? = nil
    ) {
        self.content = content
        self.foregroundColor = foregroundColor
        self.onOpenWikiLink = onOpenWikiLink
    }

    var body: some View {
        let renderedDocument = UnifiedMarkdownDocumentBuilder.makeDocument(
            preparedDocument: MarkdownDocumentPresentation.prepare(source: content, mode: .plain),
            baseURL: nil,
            configuration: .message(foregroundColor: foregroundColor)
        )

        MarkdownSelectableTextView(
            attributedText: renderedDocument.attributedText,
            onOpenWikiLink: onOpenWikiLink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let target = WikiLinkTarget(url: url), let onOpenWikiLink else {
                return .systemAction
            }
            onOpenWikiLink(target)
            return .handled
        })
    }
}

private struct MarkdownLayoutWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        guard next > 1 else { return }
        value = value > 1 ? min(value, next) : next
    }
}

private struct MarkdownLayoutWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkdownLayoutWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
    }
}

struct WikiMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.windowBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }
    }
}

private struct DocumentMarkdownStyle {
    let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = max(0.85, min(1.3, scale))
    }

    var h1FontSize: CGFloat { scaled(24) }
    var h2FontSize: CGFloat { scaled(20) }
    var h3FontSize: CGFloat { scaled(16) }
    var bodyFontSize: CGFloat { scaled(13) }
    var metadataFontSize: CGFloat { scaled(10.5) }
    var codeFontSize: CGFloat { scaled(12) }

    func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

struct MarkdownRenderedDocument: Equatable {
    let attributedText: NSAttributedString
    let tableCount: Int
    let imageAttachmentCount: Int

    static func == (lhs: MarkdownRenderedDocument, rhs: MarkdownRenderedDocument) -> Bool {
        lhs.tableCount == rhs.tableCount
            && lhs.imageAttachmentCount == rhs.imageAttachmentCount
            && lhs.attributedText.isEqual(to: rhs.attributedText)
    }
}

private enum UnifiedMarkdownDocumentBuilder {
    struct Configuration {
        let foregroundColor: Color
        let h1FontSize: CGFloat
        let h2FontSize: CGFloat
        let h3FontSize: CGFloat
        let bodyFontSize: CGFloat
        let codeFontSize: CGFloat
        let metadataFontSize: CGFloat?
        let displayTitle: String?
        let shouldRenderTitleInsideDocument: Bool

        func headingFontSize(for level: Int) -> CGFloat {
            switch level {
            case 1: h1FontSize
            case 2: h2FontSize
            case 3: h3FontSize
            default: bodyFontSize
            }
        }

        static func document(style: DocumentMarkdownStyle) -> Configuration {
            Configuration(
                foregroundColor: Theme.textPrimary,
                h1FontSize: style.h1FontSize,
                h2FontSize: style.h2FontSize,
                h3FontSize: style.h3FontSize,
                bodyFontSize: style.bodyFontSize,
                codeFontSize: style.codeFontSize,
                metadataFontSize: style.metadataFontSize,
                displayTitle: nil,
                shouldRenderTitleInsideDocument: false
            )
        }

        static func message(foregroundColor: Color) -> Configuration {
            Configuration(
                foregroundColor: foregroundColor,
                h1FontSize: 22,
                h2FontSize: 18,
                h3FontSize: 15,
                bodyFontSize: 13,
                codeFontSize: 12,
                metadataFontSize: nil,
                displayTitle: nil,
                shouldRenderTitleInsideDocument: false
            )
        }
    }

    struct BuildState {
        var attributedText = NSMutableAttributedString()
        var tableCount = 0
        var imageAttachmentCount = 0
    }

    @MainActor
    static func makeDocument(
        preparedDocument: MarkdownDocumentPresentation.PreparedDocument,
        baseURL: URL?,
        configuration: Configuration
    ) -> MarkdownRenderedDocument {
        let effectiveConfiguration = Configuration(
            foregroundColor: configuration.foregroundColor,
            h1FontSize: configuration.h1FontSize,
            h2FontSize: configuration.h2FontSize,
            h3FontSize: configuration.h3FontSize,
            bodyFontSize: configuration.bodyFontSize,
            codeFontSize: configuration.codeFontSize,
            metadataFontSize: configuration.metadataFontSize,
            displayTitle: preparedDocument.resolvedDisplayTitle,
            shouldRenderTitleInsideDocument: preparedDocument.shouldRenderTitleInsideDocument
        )

        let blocks = MarkdownDocumentRenderer.parse(preparedDocument.bodyMarkdown, baseURL: baseURL)
        var state = BuildState()

        if let metadataFontSize = effectiveConfiguration.metadataFontSize, !preparedDocument.metadata.isEmpty {
            appendBlock(
                MarkdownAttributedTextFactory.metadata(preparedDocument.metadata, fontSize: metadataFontSize),
                to: &state.attributedText
            )
        }

        if effectiveConfiguration.shouldRenderTitleInsideDocument, let title = effectiveConfiguration.displayTitle {
            appendBlock(
                MarkdownAttributedTextFactory.heading(
                    title,
                    level: 1,
                    fontSize: effectiveConfiguration.headingFontSize(for: 1),
                    color: NSColor.labelColor
                ),
                to: &state.attributedText
            )
        }

        for block in blocks {
            append(
                block,
                to: &state,
                configuration: effectiveConfiguration
            )
        }

        return MarkdownRenderedDocument(
            attributedText: NSAttributedString(attributedString: state.attributedText),
            tableCount: state.tableCount,
            imageAttachmentCount: state.imageAttachmentCount
        )
    }

    private static func append(
        _ block: RenderedMarkdownBlock,
        to state: inout BuildState,
        configuration: Configuration
    ) {
        let content: NSAttributedString

        switch block.kind {
        case .heading(let level, let text):
            content = MarkdownAttributedTextFactory.heading(
                text,
                level: level,
                fontSize: configuration.headingFontSize(for: level),
                color: NSColor.labelColor
            )
        case .paragraph(let text):
            content = MarkdownAttributedTextFactory.body(
                text,
                fontSize: configuration.bodyFontSize,
                foregroundColor: configuration.foregroundColor
            )
        case .blockquote(let blocks):
            content = MarkdownAttributedTextFactory.quote(
                blocks,
                fontSize: configuration.bodyFontSize
            )
        case .list(let items):
            content = MarkdownAttributedTextFactory.list(
                items,
                fontSize: configuration.bodyFontSize,
                foregroundColor: configuration.foregroundColor
            )
        case .codeBlock(let language, let code):
            content = MarkdownAttributedTextFactory.codeBlock(
                language: language,
                code: code,
                fontSize: configuration.codeFontSize
            )
        case .html(let html):
            content = MarkdownAttributedTextFactory.htmlBlock(
                html,
                fontSize: configuration.codeFontSize
            )
        case .table(let table):
            state.tableCount += 1
            content = MarkdownAttributedTextFactory.table(
                table,
                fontSize: configuration.bodyFontSize,
                foregroundColor: configuration.foregroundColor
            )
        case .thematicBreak:
            content = MarkdownAttributedTextFactory.divider()
        case .image(let image):
            if image.resolvedURL != nil {
                state.imageAttachmentCount += 1
            }
            content = MarkdownAttributedTextFactory.image(
                image,
                fontSize: configuration.bodyFontSize
            )
        }

        appendBlock(content, to: &state.attributedText)
    }

    private static func appendBlock(_ block: NSAttributedString, to text: inout NSMutableAttributedString) {
        guard block.length > 0 else { return }
        if text.length > 0 {
            text.append(NSAttributedString(string: "\n\n"))
        }
        text.append(block)
    }
}

private enum MarkdownAttributedTextFactory {
    static func metadata(
        _ items: [MarkdownDocumentPresentation.MetadataItem],
        fontSize: CGFloat
    ) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.defaultTabInterval = 96
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 96)]

        for (index, item) in items.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n"))
            }

            let line = NSMutableAttributedString()
            line.append(
                NSAttributedString(
                    string: "\(item.key)\t",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
            line.append(
                NSAttributedString(
                    string: item.value,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
            text.append(line)
        }

        return text
    }

    static func heading(_ text: String, level: Int, fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        let weight: NSFont.Weight
        switch level {
        case 1:
            weight = .bold
        case 2:
            weight = .semibold
        case 3:
            weight = .semibold
        default:
            weight = .semibold
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = level == 1 ? 2 : 3
        paragraphStyle.paragraphSpacing = level == 1 ? 6 : 4
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    static func body(_ source: String, fontSize: CGFloat, foregroundColor: Color) -> NSAttributedString {
        return inlineMarkdownText(
            source,
            font: .systemFont(ofSize: fontSize),
            foregroundColor: foregroundColor
        )
        .withParagraphStyle(makeBodyParagraphStyle())
    }

    static func list(_ items: [MarkdownListItem], fontSize: CGFloat, foregroundColor: Color) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let paragraphStyle = NSMutableParagraphStyle()
            let indent = CGFloat(item.level) * 18
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.headIndent = indent + 18
            paragraphStyle.lineSpacing = 3
            paragraphStyle.paragraphSpacing = 3

            let marker: String
            if let checkbox = item.checkbox {
                marker = checkbox == .checked ? "[x]" : "[ ]"
            } else {
                marker = item.isOrdered ? item.marker : "•"
            }

            let line = NSMutableAttributedString(
                string: "\(marker) ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor(foregroundColor),
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let content = inlineMarkdownText(
                item.text,
                font: .systemFont(ofSize: fontSize),
                foregroundColor: foregroundColor
            )
            let mutableContent = NSMutableAttributedString(attributedString: content)
            mutableContent.addAttributes(
                [
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: NSColor(foregroundColor),
                ],
                range: NSRange(location: 0, length: mutableContent.length)
            )
            line.append(mutableContent)
            result.append(line)
        }

        return result
    }

    static func quote(_ blocks: [RenderedMarkdownBlock], fontSize: CGFloat) -> NSAttributedString {
        let quoteText = blocks
            .compactMap(flattenBlockquoteText)
            .joined(separator: "\n\n")
        let attributed = body(quoteText, fontSize: fontSize, foregroundColor: Theme.textSecondary)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 16
        paragraphStyle.headIndent = 16
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4

        let mutable = NSMutableAttributedString(
            string: "│ ",
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
        let quotedContent = NSMutableAttributedString(attributedString: attributed)
        quotedContent.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ], range: NSRange(location: 0, length: quotedContent.length))
        mutable.append(quotedContent)
        return mutable
    }

    static func codeBlock(language: String?, code: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.headIndent = 12
        paragraphStyle.firstLineHeadIndent = 12

        let mutable = NSMutableAttributedString()
        if let language, !language.isEmpty {
            mutable.append(
                NSAttributedString(
                    string: "\(language.uppercased())\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
        }

        mutable.append(
            NSAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor(Color(nsColor: .controlBackgroundColor)),
                    .paragraphStyle: paragraphStyle,
                ]
            )
        )
        return mutable
    }

    static func htmlBlock(_ html: String, fontSize: CGFloat) -> NSAttributedString {
        codeBlock(language: "html", code: html, fontSize: fontSize)
    }

    static func table(_ table: MarkdownTable, fontSize: CGFloat, foregroundColor: Color) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let textTable = NSTextTable()
        textTable.numberOfColumns = max(table.headers.count, 1)
        textTable.layoutAlgorithm = .fixedLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setBorderColor(NSColor(Theme.border))
        textTable.setWidth(0.7, type: .absoluteValueType, for: .border)
        textTable.setWidth(8, type: .absoluteValueType, for: .padding)
        textTable.setWidth(0, type: .absoluteValueType, for: .margin)

        let headerColor = NSColor(Theme.surfaceSecondary)
        let bodyColor = NSColor(Theme.cardBackground)
        let borderColor = NSColor(Theme.border)
        let rows = [table.headers] + table.rows

        for (rowIndex, row) in rows.enumerated() {
            for columnIndex in 0..<textTable.numberOfColumns {
                let text = columnIndex < row.count ? row[columnIndex] : ""
                let block = NSTextTableBlock(
                    table: textTable,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.setValue(100 / CGFloat(textTable.numberOfColumns), type: .percentageValueType, for: .width)
                block.setWidth(0.7, type: .absoluteValueType, for: .border)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(0, type: .absoluteValueType, for: .margin)
                block.backgroundColor = rowIndex == 0 ? headerColor : bodyColor
                block.setBorderColor(borderColor)

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.textBlocks = [block]
                paragraphStyle.lineSpacing = 3
                paragraphStyle.paragraphSpacing = 2

                let content = NSMutableAttributedString(attributedString: inlineMarkdownText(
                    text,
                    font: .systemFont(ofSize: fontSize, weight: rowIndex == 0 ? .semibold : .regular),
                    foregroundColor: foregroundColor
                ))
                content.addAttributes(
                    [
                        .paragraphStyle: paragraphStyle,
                        .foregroundColor: NSColor(foregroundColor),
                    ],
                    range: NSRange(location: 0, length: content.length)
                )
                rendered.append(content)
                rendered.append(NSAttributedString(string: "\n"))
            }
        }

        return rendered.trimmingTrailingNewlines()
    }

    static func divider() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 2
        return NSAttributedString(
            string: "────────────────────────",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    static func image(_ image: MarkdownImage, fontSize: CGFloat) -> NSAttributedString {
        guard let attachment = makeImageAttachment(for: image) else {
            return imagePlaceholder(image, fontSize: fontSize)
        }

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.paragraphSpacing = 4
        attachmentString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attachmentString.length)
        )

        if !image.alt.isEmpty {
            attachmentString.append(NSAttributedString(string: "\n"))
            attachmentString.append(
                NSAttributedString(
                    string: image.alt,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: max(fontSize - 1, 11), weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
        }

        return attachmentString
    }

    static func inlineMarkdownText(_ source: String, font: NSFont, foregroundColor: Color) -> NSAttributedString {
        (try? MarkdownInlineTextStyler.makeNSAttributedString(
            from: source,
            font: font,
            foregroundColor: foregroundColor
        )) ?? NSAttributedString(
            string: source,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    static func flattenBlockquoteText(_ block: RenderedMarkdownBlock) -> String? {
        switch block.kind {
        case .paragraph(let text):
            return text
        case .heading(_, let text):
            return text
        case .list(let items):
            return items.map(markdownListItemText).joined(separator: "\n")
        case .codeBlock(let language, let code):
            let prefix = (language?.isEmpty == false ? "\(language!.uppercased())\n" : "")
            return prefix + code
        case .html(let html):
            return html
        case .blockquote(let nested):
            return nested.compactMap(flattenBlockquoteText).joined(separator: "\n\n")
        case .table(let table):
            let header = table.headers.joined(separator: " | ")
            let body = table.rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
            return ([header, body].filter { !$0.isEmpty }).joined(separator: "\n")
        case .thematicBreak:
            return nil
        case .image(let image):
            return image.alt.isEmpty ? image.source : image.alt
        }
    }

    static func markdownListItemText(_ item: MarkdownListItem) -> String {
        let indent = String(repeating: "    ", count: item.level)
        let marker: String
        if let checkbox = item.checkbox {
            marker = checkbox == .checked ? "[x]" : "[ ]"
        } else {
            marker = item.isOrdered ? item.marker : "•"
        }
        return "\(indent)\(marker) \(item.text)"
    }

    private static func makeBodyParagraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4
        return paragraphStyle
    }

    private static func makeImageAttachment(for image: MarkdownImage) -> NSTextAttachment? {
        guard let url = image.resolvedURL else { return nil }

        let nsImage: NSImage?
        if url.isFileURL {
            nsImage = NSImage(contentsOf: url)
        } else {
            nsImage = nil
        }

        guard let nsImage else { return nil }
        let maxWidth: CGFloat = 520
        let ratio = max(nsImage.size.width, 1) / max(nsImage.size.height, 1)
        let width = min(nsImage.size.width, maxWidth)
        let height = max(width / ratio, 40)

        nsImage.size = NSSize(width: width, height: height)
        let attachment = NSTextAttachment()
        attachment.image = nsImage
        return attachment
    }

    private static func imagePlaceholder(_ image: MarkdownImage, fontSize: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4

        let title = image.alt.isEmpty ? "Image" : image.alt
        let details = image.source.isEmpty ? "" : "\n\(image.source)"
        return NSAttributedString(
            string: "[\(title)]\(details)",
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor(Theme.surfaceSecondary),
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}

private struct RenderedMarkdownBlock {
    enum Kind {
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

    let kind: Kind
}

private extension RenderedMarkdownBlock {
    static func heading(level: Int, text: String) -> RenderedMarkdownBlock { .init(kind: .heading(level: level, text: text)) }
    static func paragraph(_ text: String) -> RenderedMarkdownBlock { .init(kind: .paragraph(text)) }
    static func blockquote(_ blocks: [RenderedMarkdownBlock]) -> RenderedMarkdownBlock { .init(kind: .blockquote(blocks)) }
    static func list(_ items: [MarkdownListItem]) -> RenderedMarkdownBlock { .init(kind: .list(items)) }
    static func codeBlock(language: String?, code: String) -> RenderedMarkdownBlock { .init(kind: .codeBlock(language: language, code: code)) }
    static func table(_ table: MarkdownTable) -> RenderedMarkdownBlock { .init(kind: .table(table)) }
    static var thematicBreak: RenderedMarkdownBlock { .init(kind: .thematicBreak) }
    static func html(_ html: String) -> RenderedMarkdownBlock { .init(kind: .html(html)) }
    static func image(_ image: MarkdownImage) -> RenderedMarkdownBlock { .init(kind: .image(image)) }
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

struct MarkdownImage: Equatable {
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
                .joined(separator: "\n\n")

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
            let cells = row.children.map(inlineMarkdown(from:))
            if cells.count < table.head.childCount {
                return cells + Array(repeating: "", count: table.head.childCount - cells.count)
            }
            return cells
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

private extension NSAttributedString {
    func withParagraphStyle(_ style: NSParagraphStyle) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        mutable.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }
}

private extension NSMutableAttributedString {
    func trimmingTrailingNewlines() -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        while mutable.string.hasSuffix("\n") {
            mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
        }
        return NSAttributedString(attributedString: mutable)
    }
}

private extension String {
    var trimmedMarkdown: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
@MainActor
enum DocumentMarkdownDebug {
    static func renderedDocument(
        for content: String,
        mode: MarkdownDocumentPresentation.Mode,
        baseURL: URL? = nil,
        textScale: CGFloat = 1.0
    ) -> MarkdownRenderedDocument {
        UnifiedMarkdownDocumentBuilder.makeDocument(
            preparedDocument: MarkdownDocumentPresentation.prepare(source: content, mode: mode),
            baseURL: baseURL,
            configuration: .document(style: DocumentMarkdownStyle(scale: textScale))
        )
    }
}

@MainActor
enum MessageMarkdownDebug {
    static func listItemTexts(for content: String) -> [String] {
        MarkdownDocumentRenderer.parse(content, baseURL: nil).flatMap { block -> [String] in
            guard case .list(let items) = block.kind else { return [] }
            return items.map(\.text)
        }
    }
}
#endif
