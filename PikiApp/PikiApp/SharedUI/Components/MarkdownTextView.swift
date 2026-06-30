import AppKit
import Markdown
import SwiftUI

struct DocumentMarkdownView: View {
    let presentationMode: MarkdownDocumentPresentation.Mode
    let content: String
    let baseURL: URL?
    let textScale: CGFloat
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    private var preparedDocument: MarkdownDocumentPresentation.PreparedDocument {
        MarkdownDocumentPresentation.prepare(source: content, mode: presentationMode)
    }

    private var segments: [MarkdownDisplaySegment] {
        DocumentMarkdownSegmentBuilder.make(
            document: preparedDocument,
            baseURL: baseURL
        )
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

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    DocumentMarkdownSegmentView(
                        segment: segment,
                        style: style,
                        onOpenWikiLink: onOpenWikiLink
                    )

                    if let spacing = segment.spacingAfter {
                        Color.clear
                            .frame(height: style.scaled(spacing))
                    } else if index < segments.count - 1 {
                        Color.clear
                            .frame(height: style.scaled(12))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, style.scaled(8))
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DocumentMarkdownSegmentView: View {
    let segment: MarkdownDisplaySegment
    let style: DocumentMarkdownStyle
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        switch segment.kind {
        case .textCluster(let cluster):
            MarkdownSelectableTextView(
                attributedText: style.scaled(cluster.attributedText, baseFontSize: 13),
                onOpenWikiLink: onOpenWikiLink
            )

        case .specialBlock(let specialBlock):
            switch specialBlock.kind {
            case .table(let payload):
                DocumentTableBlockView(
                    payload: payload,
                    style: style,
                    onOpenWikiLink: onOpenWikiLink
                )

            case .image(let image):
                DocumentImageBlockView(image: image, style: style)

            case .divider:
                Divider()
                    .overlay(Theme.border)
            }
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
        MessageMarkdownBlocksView(
            content: content,
            foregroundColor: foregroundColor,
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

private struct DocumentTableBlockView: View {
    let payload: DocumentTableBlockPayload
    let style: DocumentMarkdownStyle
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !payload.headers.isEmpty {
                    GridRow {
                        ForEach(payload.headers.indices, id: \.self) { index in
                            tableCell(payload.headers[index], isHeader: true)
                        }
                    }
                }

                ForEach(payload.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(payload.rows[rowIndex].indices, id: \.self) { columnIndex in
                            tableCell(payload.rows[rowIndex][columnIndex], isHeader: false)
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

    private func tableCell(_ attributed: NSAttributedString, isHeader: Bool) -> some View {
        MarkdownSelectableTextView(
            attributedText: style.scaled(attributed, baseFontSize: 13),
            onOpenWikiLink: onOpenWikiLink
        )
        .frame(minWidth: style.scaled(140), maxWidth: style.scaled(300), alignment: .leading)
        .padding(.horizontal, style.scaled(12))
        .padding(.vertical, style.scaled(10))
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

private struct DocumentImageBlockView: View {
    let image: MarkdownImage
    let style: DocumentMarkdownStyle

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
        HStack(alignment: .top, spacing: style.scaled(10)) {
            Image(systemName: "photo")
                .font(.system(size: style.scaled(15), weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(image.alt.isEmpty ? "Image" : image.alt)
                    .font(.system(size: style.bodyFontSize, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                if !image.source.isEmpty {
                    Text(image.source)
                        .font(.system(size: style.scaled(11), design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(style.scaled(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 0.7)
        )
        .clipShape(.rect(cornerRadius: 8))
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

    func scaled(_ attributedText: NSAttributedString, baseFontSize: CGFloat) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont else {
                mutable.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: scaled(baseFontSize)),
                    range: range
                )
                return
            }

            let descriptor = font.fontDescriptor
            let scaledFont = NSFont(descriptor: descriptor, size: scaled(font.pointSize)) ?? font
            mutable.addAttribute(.font, value: scaledFont, range: range)
        }

        return mutable
    }
}

struct MarkdownDisplaySegment: Equatable {
    let kind: Kind
    let spacingAfter: CGFloat?

    enum Kind: Equatable {
        case textCluster(MarkdownTextCluster)
        case specialBlock(MarkdownSpecialBlock)
    }
}

struct MarkdownTextCluster: Equatable {
    let attributedText: NSAttributedString

    static func == (lhs: MarkdownTextCluster, rhs: MarkdownTextCluster) -> Bool {
        lhs.attributedText.isEqual(to: rhs.attributedText)
    }
}

struct MarkdownSpecialBlock: Equatable {
    let kind: Kind

    enum Kind: Equatable {
        case table(DocumentTableBlockPayload)
        case image(MarkdownImage)
        case divider
    }
}

private struct MarkdownSegmentAccumulator {
    private(set) var segments: [MarkdownDisplaySegment] = []
    private var pendingText = NSMutableAttributedString()
    private var pendingSpacingAfter: CGFloat?

    mutating func appendText(_ attributedText: NSAttributedString, spacingAfter: CGFloat) {
        guard attributedText.length > 0 else { return }
        if pendingText.length > 0 {
            pendingText.append(NSAttributedString(string: "\n\n"))
        }
        pendingText.append(attributedText)
        pendingSpacingAfter = spacingAfter
    }

    mutating func appendSpecial(_ kind: MarkdownSpecialBlock.Kind, spacingAfter: CGFloat?) {
        flushTextCluster()
        segments.append(
            MarkdownDisplaySegment(
                kind: .specialBlock(MarkdownSpecialBlock(kind: kind)),
                spacingAfter: spacingAfter
            )
        )
    }

    mutating func finish() -> [MarkdownDisplaySegment] {
        flushTextCluster()
        return segments
    }

    private mutating func flushTextCluster() {
        guard pendingText.length > 0 else { return }
        segments.append(
            MarkdownDisplaySegment(
                kind: .textCluster(
                    MarkdownTextCluster(
                        attributedText: NSAttributedString(attributedString: pendingText)
                    )
                ),
                spacingAfter: pendingSpacingAfter
            )
        )
        pendingText = NSMutableAttributedString()
        pendingSpacingAfter = nil
    }
}

private enum MarkdownAttributedTextFactory {
    static func metadata(_ items: [MarkdownDocumentPresentation.MetadataItem]) -> NSAttributedString {
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
                        .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
            line.append(
                NSAttributedString(
                    string: item.value,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10.5),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
            text.append(line)
        }

        return text
    }

    static func heading(_ text: String, level: Int, color: NSColor, isMessage: Bool) -> NSAttributedString {
        let size: CGFloat
        let weight: NSFont.Weight
        switch level {
        case 1:
            size = isMessage ? 22 : 24
            weight = .bold
        case 2:
            size = isMessage ? 18 : 20
            weight = .semibold
        case 3:
            size = isMessage ? 15 : 16
            weight = .semibold
        default:
            size = 13
            weight = .semibold
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = level == 1 ? 2 : 3
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    static func body(_ source: String, fontSize: CGFloat, foregroundColor: Color) -> NSAttributedString {
        inlineMarkdownText(
            source,
            font: .system(size: fontSize),
            foregroundColor: foregroundColor
        )
    }

    static func list(_ items: [MarkdownListItem], fontSize: CGFloat, foregroundColor: Color) -> NSAttributedString {
        body(
            items.map(markdownListItemText).joined(separator: "\n"),
            fontSize: fontSize,
            foregroundColor: foregroundColor
        )
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
        paragraphStyle.paragraphSpacing = 2

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
                    .backgroundColor: NSColor.controlBackgroundColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
        )
        return mutable
    }

    static func htmlBlock(_ html: String, fontSize: CGFloat) -> NSAttributedString {
        codeBlock(language: "html", code: html, fontSize: fontSize)
    }

    static func tablePayload(_ table: MarkdownTable, foregroundColor: Color) -> DocumentTableBlockPayload {
        DocumentTableBlockPayload(
            headers: table.headers.map {
                inlineMarkdownText(
                    $0,
                    font: .system(size: 12, weight: .semibold),
                    foregroundColor: Theme.textPrimary
                )
            },
            rows: table.rows.map { row in
                row.map {
                    inlineMarkdownText(
                        $0,
                        font: .system(size: 12),
                        foregroundColor: foregroundColor
                    )
                }
            }
        )
    }

    static func inlineMarkdownText(_ source: String, font: Font, foregroundColor: Color) -> NSAttributedString {
        (try? MarkdownInlineTextStyler.makeNSAttributedString(
            from: source,
            font: font,
            foregroundColor: foregroundColor
        )) ?? NSAttributedString(
            string: source,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
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

    static func flattenBlockquoteText(_ block: RenderedMarkdownBlock) -> String? {
        switch block {
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
}

@MainActor
private enum DocumentMarkdownSegmentBuilder {
    static func make(
        document: MarkdownDocumentPresentation.PreparedDocument,
        baseURL: URL?
    ) -> [MarkdownDisplaySegment] {
        var accumulator = MarkdownSegmentAccumulator()

        if !document.metadata.isEmpty {
            accumulator.appendText(MarkdownAttributedTextFactory.metadata(document.metadata), spacingAfter: 28)
        }

        if document.shouldRenderTitleInsideDocument, let title = document.resolvedDisplayTitle {
            accumulator.appendText(
                MarkdownAttributedTextFactory.heading(
                    title,
                    level: 1,
                    color: NSColor.labelColor,
                    isMessage: false
                ),
                spacingAfter: 22
            )
        }

        let blocks = MarkdownDocumentRenderer.parse(document.bodyMarkdown, baseURL: baseURL)
        for block in blocks {
            append(block, to: &accumulator)
        }

        return accumulator.finish()
    }

    private static func append(_ block: RenderedMarkdownBlock, to accumulator: inout MarkdownSegmentAccumulator) {
        switch block {
        case .heading(let level, let text):
            accumulator.appendText(
                MarkdownAttributedTextFactory.heading(
                    text,
                    level: level,
                    color: NSColor.labelColor,
                    isMessage: false
                ),
                spacingAfter: headingSpacingAfter(level)
            )
        case .paragraph(let text):
            accumulator.appendText(
                MarkdownAttributedTextFactory.body(text, fontSize: 13, foregroundColor: Theme.textPrimary),
                spacingAfter: 14
            )
        case .blockquote(let blocks):
            accumulator.appendText(
                MarkdownAttributedTextFactory.quote(blocks, fontSize: 13),
                spacingAfter: 16
            )
        case .list(let items):
            accumulator.appendText(
                MarkdownAttributedTextFactory.list(items, fontSize: 13, foregroundColor: Theme.textPrimary),
                spacingAfter: 14
            )
        case .codeBlock(let language, let code):
            accumulator.appendText(
                MarkdownAttributedTextFactory.codeBlock(language: language, code: code, fontSize: 12),
                spacingAfter: 18
            )
        case .html(let html):
            accumulator.appendText(
                MarkdownAttributedTextFactory.htmlBlock(html, fontSize: 12),
                spacingAfter: 18
            )
        case .table(let table):
            accumulator.appendSpecial(
                .table(MarkdownAttributedTextFactory.tablePayload(table, foregroundColor: Theme.textSecondary)),
                spacingAfter: 18
            )
        case .thematicBreak:
            accumulator.appendSpecial(.divider, spacingAfter: 18)
        case .image(let image):
            accumulator.appendSpecial(.image(image), spacingAfter: 18)
        }
    }

    private static func headingSpacingAfter(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            return 20
        case 2:
            return 14
        case 3:
            return 10
        default:
            return 8
        }
    }
}

@MainActor
private enum MessageMarkdownSegmentBuilder {
    static func make(content: String, foregroundColor: Color) -> [MarkdownDisplaySegment] {
        var accumulator = MarkdownSegmentAccumulator()
        let blocks = MarkdownDocumentRenderer.parse(content, baseURL: nil)
        for block in blocks {
            append(block, foregroundColor: foregroundColor, to: &accumulator)
        }
        return accumulator.finish()
    }

    private static func append(
        _ block: RenderedMarkdownBlock,
        foregroundColor: Color,
        to accumulator: inout MarkdownSegmentAccumulator
    ) {
        switch block {
        case .heading(let level, let text):
            accumulator.appendText(
                MarkdownAttributedTextFactory.heading(
                    text,
                    level: level,
                    color: NSColor.labelColor,
                    isMessage: true
                ),
                spacingAfter: level <= 2 ? 10 : 6
            )
        case .paragraph(let text):
            accumulator.appendText(
                MarkdownAttributedTextFactory.body(text, fontSize: 13, foregroundColor: foregroundColor),
                spacingAfter: 10
            )
        case .blockquote(let blocks):
            accumulator.appendText(
                MarkdownAttributedTextFactory.quote(blocks, fontSize: 13),
                spacingAfter: 12
            )
        case .list(let items):
            accumulator.appendText(
                MarkdownAttributedTextFactory.list(items, fontSize: 13, foregroundColor: foregroundColor),
                spacingAfter: 10
            )
        case .codeBlock(let language, let code):
            accumulator.appendText(
                MarkdownAttributedTextFactory.codeBlock(language: language, code: code, fontSize: 12),
                spacingAfter: 12
            )
        case .html(let html):
            accumulator.appendText(
                MarkdownAttributedTextFactory.htmlBlock(html, fontSize: 12),
                spacingAfter: 12
            )
        case .table(let table):
            accumulator.appendSpecial(
                .table(MarkdownAttributedTextFactory.tablePayload(table, foregroundColor: Theme.textSecondary)),
                spacingAfter: 12
            )
        case .thematicBreak:
            accumulator.appendSpecial(.divider, spacingAfter: 8)
        case .image(let image):
            accumulator.appendSpecial(.image(image), spacingAfter: 12)
        }
    }
}

private struct MessageMarkdownBlocksView: View {
    let content: String
    let foregroundColor: Color
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    private var segments: [MarkdownDisplaySegment] {
        MessageMarkdownSegmentBuilder.make(
            content: content,
            foregroundColor: foregroundColor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                MessageMarkdownSegmentView(
                    segment: segment,
                    onOpenWikiLink: onOpenWikiLink
                )

                if let spacing = segment.spacingAfter {
                    Color.clear
                        .frame(height: spacing)
                } else if index < segments.count - 1 {
                    Color.clear
                        .frame(height: 10)
                }
            }
        }
    }
}

private struct MessageMarkdownSegmentView: View {
    let segment: MarkdownDisplaySegment
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        switch segment.kind {
        case .textCluster(let cluster):
            MarkdownSelectableTextView(
                attributedText: cluster.attributedText,
                onOpenWikiLink: onOpenWikiLink
            )

        case .specialBlock(let specialBlock):
            switch specialBlock.kind {
            case .table(let payload):
                MessageMarkdownTableView(
                    payload: payload,
                    onOpenWikiLink: onOpenWikiLink
                )

            case .image(let image):
                MessageMarkdownImageView(image: image)

            case .divider:
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct MessageMarkdownTableView: View {
    let payload: DocumentTableBlockPayload
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(payload.headers.indices, id: \.self) { column in
                        tableCell(payload.headers[column], isHeader: true)
                    }
                }

                ForEach(payload.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(payload.rows[rowIndex].indices, id: \.self) { column in
                            tableCell(payload.rows[rowIndex][column], isHeader: false)
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

    private func tableCell(_ value: NSAttributedString, isHeader: Bool) -> some View {
        MarkdownSelectableTextView(
            attributedText: value,
            onOpenWikiLink: onOpenWikiLink
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

private struct MessageMarkdownImageView: View {
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
            Image(systemName: "photo")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(image.alt.isEmpty ? "Image" : image.alt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                if !image.source.isEmpty {
                    Text(image.source)
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

struct DocumentTableBlockPayload: Equatable {
    let headers: [NSAttributedString]
    let rows: [[NSAttributedString]]

    static func == (lhs: DocumentTableBlockPayload, rhs: DocumentTableBlockPayload) -> Bool {
        guard lhs.headers.count == rhs.headers.count, lhs.rows.count == rhs.rows.count else { return false }
        guard zip(lhs.headers, rhs.headers).allSatisfy({ $0.isEqual(to: $1) }) else { return false }
        for (leftRow, rightRow) in zip(lhs.rows, rhs.rows) {
            guard leftRow.count == rightRow.count else { return false }
            guard zip(leftRow, rightRow).allSatisfy({ $0.isEqual(to: $1) }) else { return false }
        }
        return true
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

private extension String {
    var trimmedMarkdown: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
@MainActor
enum DocumentMarkdownDebug {
    static func segments(
        for content: String,
        mode: MarkdownDocumentPresentation.Mode,
        baseURL: URL? = nil
    ) -> [MarkdownDisplaySegment] {
        DocumentMarkdownSegmentBuilder.make(
            document: MarkdownDocumentPresentation.prepare(source: content, mode: mode),
            baseURL: baseURL
        )
    }
}

@MainActor
enum MessageMarkdownDebug {
    static func listItemTexts(for content: String) -> [String] {
        MarkdownDocumentRenderer.parse(content, baseURL: nil).flatMap { block -> [String] in
            guard case .list(let items) = block else { return [] }
            return items.map(\.text)
        }
    }
}
#endif
