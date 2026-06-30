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

    private var blocks: [DocumentMarkdownBlock] {
        DocumentMarkdownBlockBuilder.make(
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
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    DocumentMarkdownBlockView(
                        block: block,
                        style: style,
                        baseURL: baseURL,
                        onOpenWikiLink: onOpenWikiLink
                    )

                    if let spacing = block.spacingAfter {
                        Color.clear
                            .frame(height: style.scaled(spacing))
                    } else if index < blocks.count - 1 {
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

private struct DocumentMarkdownBlockView: View {
    let block: DocumentMarkdownBlock
    let style: DocumentMarkdownStyle
    let baseURL: URL?
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        switch block.kind {
        case .metadata(let items):
            DocumentMetadataStrip(items: items, style: style)

        case .heading(let payload):
            DocumentHeadingView(payload: payload, style: style)

        case .text(let payload):
            DocumentTextBlockView(
                payload: payload,
                style: style,
                onOpenWikiLink: onOpenWikiLink
            )

        case .table(let payload):
            DocumentTableBlockView(
                payload: payload,
                style: style,
                onOpenWikiLink: onOpenWikiLink
            )

        case .codeBlock(let payload):
            DocumentCodeBlockView(payload: payload, style: style)

        case .image(let image):
            DocumentImageBlockView(image: image, style: style)

        case .divider:
            Divider()
                .overlay(Theme.border)
        }
    }
}

private struct DocumentMetadataStrip: View {
    let items: [MarkdownDocumentPresentation.MetadataItem]
    let style: DocumentMarkdownStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.scaled(8)) {
            ForEach(items, id: \.key) { item in
                HStack(alignment: .firstTextBaseline, spacing: style.scaled(12)) {
                    Text(item.key)
                        .font(.system(size: style.metadataFontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: style.scaled(78), alignment: .leading)

                    Text(item.value)
                        .font(.system(size: style.metadataFontSize))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DocumentHeadingView: View {
    let payload: DocumentHeadingPayload
    let style: DocumentMarkdownStyle

    var body: some View {
        Text(payload.text)
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(style.scaled(payload.lineSpacing))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var font: Font {
        switch payload.level {
        case 1:
            return .system(size: style.h1FontSize, weight: .bold)
        case 2:
            return .system(size: style.h2FontSize, weight: .semibold)
        case 3:
            return .system(size: style.h3FontSize, weight: .semibold)
        default:
            return .system(size: style.bodyFontSize + style.scaled(1), weight: .semibold)
        }
    }
}

private struct DocumentTextBlockView: View {
    let payload: DocumentTextBlockPayload
    let style: DocumentMarkdownStyle
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        switch payload.style {
        case .blockquote:
            HStack(alignment: .top, spacing: style.scaled(10)) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.border)
                    .frame(width: style.scaled(3))
                MarkdownSelectableTextView(
                    attributedText: style.scaled(payload.attributedText, baseFontSize: 13),
                    onOpenWikiLink: onOpenWikiLink
                )
            }

        case .body:
            MarkdownSelectableTextView(
                attributedText: style.scaled(payload.attributedText, baseFontSize: 13),
                onOpenWikiLink: onOpenWikiLink
            )
        }
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

private struct DocumentCodeBlockView: View {
    let payload: DocumentCodeBlockPayload
    let style: DocumentMarkdownStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = payload.language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: style.metadataFontSize, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, style.scaled(12))
                    .padding(.vertical, style.scaled(7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(payload.code)
                    .font(.system(size: style.codeFontSize, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(style.scaled(12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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

private struct MessageMarkdownBlocksView: View {
    let content: String
    let foregroundColor: Color
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    private var blocks: [RenderedMarkdownBlock] {
        MarkdownDocumentRenderer.parse(content, baseURL: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MessageMarkdownBlockView(
                    block: block,
                    foregroundColor: foregroundColor,
                    onOpenWikiLink: onOpenWikiLink
                )
            }
        }
    }
}

private struct MessageMarkdownBlockView: View {
    let block: RenderedMarkdownBlock
    let foregroundColor: Color
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(
                text,
                font: headingFont(level),
                foregroundColor: foregroundColor,
                onOpenWikiLink: onOpenWikiLink
            )
            .padding(.top, level <= 2 ? 8 : 4)
            .padding(.bottom, 2)

        case .paragraph(let text):
            InlineMarkdownText(
                text,
                font: .system(size: 13),
                foregroundColor: foregroundColor,
                onOpenWikiLink: onOpenWikiLink
            )

        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.border)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, nestedBlock in
                        MessageMarkdownBlockView(
                            block: nestedBlock,
                            foregroundColor: Theme.textSecondary,
                            onOpenWikiLink: onOpenWikiLink
                        )
                    }
                }
            }
            .padding(.vertical, 4)

        case .list(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        listMarker(for: item)
                        VStack(alignment: .leading, spacing: 0) {
                            InlineMarkdownText(
                                item.text,
                                font: .system(size: 13),
                                foregroundColor: foregroundColor,
                                onOpenWikiLink: onOpenWikiLink
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 1)
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }

        case .codeBlock(let language, let code):
            MessageCodeBlockView(language: language, code: code)

        case .table(let table):
            MessageMarkdownTableView(table: table)

        case .thematicBreak:
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.vertical, 8)

        case .html(let html):
            MessageCodeBlockView(language: "html", code: html)

        case .image(let image):
            MessageMarkdownImageView(image: image)
        }
    }

    @ViewBuilder
    private func listMarker(for item: MarkdownListItem) -> some View {
        if let checkbox = item.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(checkbox == .checked ? Theme.success : Theme.textTertiary)
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 1)
        } else {
            Text(item.marker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: item.isOrdered ? 28 : 16, alignment: .trailing)
                .padding(.top, 1)
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
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    init(_ source: String, font: Font, foregroundColor: Color, onOpenWikiLink: ((WikiLinkTarget) -> Void)? = nil) {
        self.source = source
        self.font = font
        self.foregroundColor = foregroundColor
        self.onOpenWikiLink = onOpenWikiLink
    }

    var body: some View {
        if let attributedText {
            MarkdownSelectableTextView(
                attributedText: attributedText,
                onOpenWikiLink: onOpenWikiLink
            )
        } else {
            Text(source)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    private var attributedText: NSAttributedString? {
        try? MarkdownInlineTextStyler.makeNSAttributedString(
            from: source,
            font: font,
            foregroundColor: foregroundColor
        )
    }
}

private struct MessageCodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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

private struct MessageMarkdownTableView: View {
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

struct DocumentMarkdownBlock: Equatable {
    let kind: Kind
    let spacingAfter: CGFloat?

    enum Kind: Equatable {
        case metadata([MarkdownDocumentPresentation.MetadataItem])
        case heading(DocumentHeadingPayload)
        case text(DocumentTextBlockPayload)
        case table(DocumentTableBlockPayload)
        case codeBlock(DocumentCodeBlockPayload)
        case image(MarkdownImage)
        case divider
    }
}

struct DocumentHeadingPayload: Equatable {
    let level: Int
    let text: String
    let lineSpacing: CGFloat
}

struct DocumentTextBlockPayload: Equatable {
    enum Style: Equatable {
        case body
        case blockquote
    }

    let attributedText: NSAttributedString
    let style: Style

    static func == (lhs: DocumentTextBlockPayload, rhs: DocumentTextBlockPayload) -> Bool {
        lhs.style == rhs.style && lhs.attributedText.isEqual(to: rhs.attributedText)
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

struct DocumentCodeBlockPayload: Equatable {
    let language: String?
    let code: String
}

@MainActor
private enum DocumentMarkdownBlockBuilder {
    static func make(
        document: MarkdownDocumentPresentation.PreparedDocument,
        baseURL: URL?
    ) -> [DocumentMarkdownBlock] {
        var result: [DocumentMarkdownBlock] = []

        if !document.metadata.isEmpty {
            result.append(
                DocumentMarkdownBlock(
                    kind: .metadata(document.metadata),
                    spacingAfter: 28
                )
            )
        }

        if document.shouldRenderTitleInsideDocument, let title = document.resolvedDisplayTitle {
            result.append(
                DocumentMarkdownBlock(
                    kind: .heading(
                        DocumentHeadingPayload(level: 1, text: title, lineSpacing: 2)
                    ),
                    spacingAfter: 22
                )
            )
        }

        let blocks = MarkdownDocumentRenderer.parse(document.bodyMarkdown, baseURL: baseURL)
        for block in blocks {
            if let converted = map(block) {
                result.append(converted)
            }
        }

        return result
    }

    private static func map(_ block: RenderedMarkdownBlock) -> DocumentMarkdownBlock? {
        switch block {
        case .heading(let level, let text):
            return DocumentMarkdownBlock(
                kind: .heading(
                    DocumentHeadingPayload(
                        level: level,
                        text: text,
                        lineSpacing: level == 1 ? 2 : 3
                    )
                ),
                spacingAfter: headingSpacingAfter(level)
            )

        case .paragraph(let text):
            return textBlock(text, style: .body, spacingAfter: 14)

        case .blockquote(let blocks):
            let quoteText = blocks
                .compactMap(flattenBlockquoteText)
                .joined(separator: "\n\n")
            return textBlock(quoteText, style: .blockquote, spacingAfter: 16)

        case .list(let items):
            let listText = items.map(renderListItem).joined(separator: "\n")
            return textBlock(listText, style: .body, spacingAfter: 14)

        case .codeBlock(let language, let code):
            return DocumentMarkdownBlock(
                kind: .codeBlock(DocumentCodeBlockPayload(language: language, code: code)),
                spacingAfter: 18
            )

        case .table(let table):
            return DocumentMarkdownBlock(
                kind: .table(
                    DocumentTableBlockPayload(
                        headers: table.headers.map { inlineMarkdownText($0) },
                        rows: table.rows.map { row in row.map(inlineMarkdownText) }
                    )
                ),
                spacingAfter: 18
            )

        case .thematicBreak:
            return DocumentMarkdownBlock(
                kind: .divider,
                spacingAfter: 18
            )

        case .html(let html):
            return DocumentMarkdownBlock(
                kind: .codeBlock(DocumentCodeBlockPayload(language: "html", code: html)),
                spacingAfter: 18
            )

        case .image(let image):
            return DocumentMarkdownBlock(
                kind: .image(image),
                spacingAfter: 18
            )
        }
    }

    private static func textBlock(
        _ text: String,
        style: DocumentTextBlockPayload.Style,
        spacingAfter: CGFloat
    ) -> DocumentMarkdownBlock? {
        let attributed = inlineMarkdownText(text)
        guard attributed.length > 0 else { return nil }
        return DocumentMarkdownBlock(
            kind: .text(
                DocumentTextBlockPayload(
                    attributedText: attributed,
                    style: style
                )
            ),
            spacingAfter: spacingAfter
        )
    }

    private static func flattenBlockquoteText(_ block: RenderedMarkdownBlock) -> String? {
        switch block {
        case .paragraph(let text):
            return text
        case .heading(_, let text):
            return text
        case .list(let items):
            return items.map(renderListItem).joined(separator: "\n")
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

    private static func renderListItem(_ item: MarkdownListItem) -> String {
        let indent = String(repeating: "    ", count: item.level)
        let marker: String
        if let checkbox = item.checkbox {
            marker = checkbox == .checked ? "[x]" : "[ ]"
        } else {
            marker = item.isOrdered ? item.marker : "•"
        }
        return "\(indent)\(marker) \(item.text)"
    }

    private static func inlineMarkdownText(_ source: String) -> NSAttributedString {
        (try? MarkdownInlineTextStyler.makeNSAttributedString(
            from: source,
            font: .system(size: 13),
            foregroundColor: Theme.textPrimary
        )) ?? NSAttributedString(
            string: source,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
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
    static func blocks(
        for content: String,
        mode: MarkdownDocumentPresentation.Mode,
        baseURL: URL? = nil
    ) -> [DocumentMarkdownBlock] {
        DocumentMarkdownBlockBuilder.make(
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
