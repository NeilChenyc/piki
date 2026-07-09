import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum InspirationEditorReturnAction: Equatable {
    case submit
    case insertNewline
}

enum InspirationEditorKeyPolicy {
    static func returnAction(for flags: NSEvent.ModifierFlags) -> InspirationEditorReturnAction {
        let modifiers = flags.intersection([.shift, .control, .option, .command])
        return modifiers == .shift ? .insertNewline : .submit
    }
}

struct InspirationPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(InspirationViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 0) {
            header(
                searchQuery: $viewModel.searchQuery,
                isUpdatingWiki: viewModel.isCompiling,
                canUpdateWiki: appState.isConnected,
                onUpdateWiki: {
                    Task { await viewModel.updateWiki(appState: appState) }
                }
            )
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            InspirationComposer(
                text: $viewModel.draftText,
                attachments: viewModel.draftAttachments,
                isSaving: viewModel.isSaving,
                onInsertToken: insertDraftToken(_:),
                onAttachImage: chooseDraftImage,
                onPasteImage: { image in
                    Task { await viewModel.addDraftPastedImage(image, appState: appState) }
                },
                onRemoveAttachment: viewModel.removeDraftAttachment(_:),
                onSubmit: {
                    Task { await viewModel.submitDraft(appState: appState) }
                },
                attachmentURL: attachmentURL(_:)
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 16)

            Divider()

            memoList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.secondaryPanelBackground)
        .task(id: appState.vaultPath) {
            await viewModel.loadIfNeeded(appState: appState)
        }
        .task(id: viewModel.searchQuery) {
            await viewModel.load(appState: appState)
        }
    }

    private func header(
        searchQuery: Binding<String>,
        isUpdatingWiki: Bool,
        canUpdateWiki: Bool,
        onUpdateWiki: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("随手记")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                Button(action: onUpdateWiki) {
                    HStack(spacing: 6) {
                        if isUpdatingWiki {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text("灵感注入")
                    }
                    .frame(minWidth: 86, minHeight: 28)
                }
                .controlSize(.regular)
                .disabled(isUpdatingWiki || !canUpdateWiki)
                .help("把最新的随手记内容增量注入到 Wiki 中。AI 会自动识别重要和有价值的随手记内容，并整理进合适的 Wiki 页面。")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)

                TextField("搜索灵感", text: searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchQuery.wrappedValue.isEmpty {
                    Button {
                        searchQuery.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.subtleFill)
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }

                if viewModel.isLoading && viewModel.items.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载随手记...")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                } else if viewModel.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textTertiary)
                        Text("还没有随手记")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("零散想法先放在这里。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                } else {
                    ForEach(viewModel.items) { item in
                        if viewModel.editingId == item.id {
                            InspirationEditCard(
                                text: Binding(
                                    get: { viewModel.editingText },
                                    set: { viewModel.editingText = $0 }
                                ),
                                attachments: viewModel.editingAttachments,
                                isSaving: viewModel.isSaving,
                                onAttachImage: chooseEditingImage,
                                onPasteImage: { image in
                                    Task { await viewModel.addEditingPastedImage(image, appState: appState) }
                                },
                                onRemoveAttachment: viewModel.removeEditingAttachment(_:),
                                onSave: {
                                    Task { await viewModel.saveEditing(appState: appState) }
                                },
                                onCancel: viewModel.cancelEditing,
                                attachmentURL: attachmentURL(_:)
                            )
                            .padding(.horizontal, 18)
                        } else {
                            InspirationMemoCard(
                                item: item,
                                attachmentURL: attachmentURL(_:),
                                onEdit: { viewModel.beginEditing(item) },
                                onDelete: {
                                    Task { await viewModel.deleteInspiration(item, appState: appState) }
                                }
                            )
                            .padding(.horizontal, 18)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Theme.primaryPanelBackground.opacity(0.35))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if viewModel.isCompiling {
                ProgressView().controlSize(.small)
            }
            Text(viewModel.statusMessage ?? "\(viewModel.items.count) 条随手记")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer()
        }
    }

    private func insertDraftToken(_ token: String) {
        if viewModel.draftText.isEmpty {
            viewModel.draftText = token
        } else {
            viewModel.draftText += viewModel.draftText.hasSuffix("\n") ? token : "\n\(token)"
        }
    }

    private func chooseDraftImage() {
        chooseImage { url in
            Task { await viewModel.addDraftImage(url, appState: appState) }
        }
    }

    private func chooseEditingImage() {
        chooseImage { url in
            Task { await viewModel.addEditingImage(url, appState: appState) }
        }
    }

    private func chooseImage(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func attachmentURL(_ attachment: InspirationAttachmentDTO) -> URL? {
        if let bufferedPath = attachment.bufferedPath {
            return URL(fileURLWithPath: bufferedPath)
        }
        guard let relativePath = attachment.path else { return nil }
        return appState.vaultPath?.appendingPathComponent(relativePath)
    }
}

private struct InspirationComposer: View {
    @Binding var text: String
    let attachments: [InspirationAttachmentDTO]
    let isSaving: Bool
    let onInsertToken: (String) -> Void
    let onAttachImage: () -> Void
    let onPasteImage: (NSImage) -> Void
    let onRemoveAttachment: (InspirationAttachmentDTO) -> Void
    let onSubmit: () -> Void
    let attachmentURL: (InspirationAttachmentDTO) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                InspirationTextEditor(
                    text: $text,
                    fontSize: 13,
                    onSubmit: onSubmit,
                    onPasteImages: { images in
                        images.forEach(onPasteImage)
                    }
                )
                    .frame(minHeight: 72, maxHeight: 130)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("现在的想法是...")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 1)
                        .padding(.leading, 0)
                        .allowsHitTesting(false)
                }
            }

            if !attachments.isEmpty {
                InspirationAttachmentStrip(
                    attachments: attachments,
                    onRemove: onRemoveAttachment,
                    onAdd: onAttachImage,
                    attachmentURL: attachmentURL
                )
            }

            HStack(spacing: 10) {
                InspirationToolbarButton(systemName: "number", help: "添加标签") { onInsertToken("# ") }
                InspirationToolbarButton(systemName: "photo", help: "添加图片", action: onAttachImage)
                Divider().frame(height: 18)
                InspirationToolbarButton(systemName: "bold", help: "粗体") { onInsertToken("**重点**") }
                InspirationToolbarButton(systemName: "list.bullet", help: "项目列表") { onInsertToken("- ") }
                InspirationToolbarButton(systemName: "list.number", help: "编号列表") { onInsertToken("1. ") }
                Divider().frame(height: 18)
                InspirationToolbarButton(systemName: "at", help: "提及实体") { onInsertToken("@") }

                Spacer(minLength: 0)

                Button(action: onSubmit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSubmit ? Color.white : Theme.textTertiary)
                        .frame(width: 42, height: 32)
                        .background(canSubmit ? Theme.accent : Theme.subtleFill)
                        .clipShape(.rect(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isSaving)
                .help("保存随手记")
            }
        }
        .padding(16)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 0.8)
        )
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct InspirationMemoCard: View {
    let item: InspirationDTO
    let attachmentURL: (InspirationAttachmentDTO) -> URL?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(displayDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                InspirationStatusBadge(status: item.compileStatus)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.error.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除随手记")
            }

            Text(item.content)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.attachments.isEmpty {
                InspirationAttachmentStrip(
                    attachments: item.attachments,
                    onRemove: nil,
                    onAdd: nil,
                    attachmentURL: attachmentURL
                )
            }
        }
        .padding(10)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
        )
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var displayDate: String {
        guard let date = Date.fromInspirationISO8601(item.createdAt) else {
            return item.createdAt
        }
        return date.formatted(date: .numeric, time: .standard)
    }
}

private struct InspirationEditCard: View {
    @Binding var text: String
    let attachments: [InspirationAttachmentDTO]
    let isSaving: Bool
    let onAttachImage: () -> Void
    let onPasteImage: (NSImage) -> Void
    let onRemoveAttachment: (InspirationAttachmentDTO) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let attachmentURL: (InspirationAttachmentDTO) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspirationTextEditor(
                text: $text,
                fontSize: 15,
                onSubmit: onSave,
                onPasteImages: { images in
                    images.forEach(onPasteImage)
                }
            )
                .frame(minHeight: 120)
                .padding(8)
                .background(Theme.primaryPanelBackground)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 0.6)
                )

            if !attachments.isEmpty {
                InspirationAttachmentStrip(
                    attachments: attachments,
                    onRemove: onRemoveAttachment,
                    onAdd: onAttachImage,
                    attachmentURL: attachmentURL
                )
            }

            HStack(spacing: 10) {
                InspirationToolbarButton(systemName: "photo", help: "添加图片", action: onAttachImage)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("取消")

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 28)
                        .background(Theme.accent)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .help("保存编辑")
            }
        }
        .padding(14)
        .background(Theme.elevatedCardBackground)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct InspirationToolbarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct InspirationAttachmentStrip: View {
    let attachments: [InspirationAttachmentDTO]
    let onRemove: ((InspirationAttachmentDTO) -> Void)?
    let onAdd: (() -> Void)?
    let attachmentURL: (InspirationAttachmentDTO) -> URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.filename) { attachment in
                    ZStack(alignment: .topTrailing) {
                        InspirationAttachmentThumbnail(url: attachmentURL(attachment))
                        if let onRemove {
                            Button {
                                onRemove(attachment)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white, .black.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    }
                    .help(attachment.filename)
                }

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 64, height: 48)
                            .background(Theme.elevatedCardBackground.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(
                                        Theme.border,
                                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .clipShape(.rect(cornerRadius: 7))
                    .help("添加图片")
                }
            }
        }
    }
}

private struct InspirationAttachmentThumbnail: View {
    let url: URL?
    @State private var showFullSize = false

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .onTapGesture { showFullSize = true }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 64, height: 48)
        .background(Theme.subtleFill)
        .clipShape(.rect(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
        )
        .popover(isPresented: $showFullSize) {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480, maxHeight: 360)
                    .padding(8)
            }
        }
    }

    private var nsImage: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct InspirationStatusBadge: View {
    let status: String

    var body: some View {
        Text(presentation.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(presentation.color.opacity(0.1))
            .clipShape(.capsule)
    }

    private var presentation: InspirationStatusPresentation {
        InspirationStatusPresentation.make(for: status)
    }
}

enum InspirationStatusTone: Equatable {
    case pending
    case processing
    case compiled
    case failed
}

struct InspirationStatusPresentation {
    let label: String
    let tone: InspirationStatusTone

    var color: Color {
        switch tone {
        case .pending: Theme.textTertiary
        case .processing: Theme.warning
        case .compiled: Theme.success
        case .failed: Theme.error
        }
    }

    static func make(for status: String) -> InspirationStatusPresentation {
        switch status {
        case "processing":
            InspirationStatusPresentation(label: "整理中", tone: .processing)
        case "compiled", "completed":
            InspirationStatusPresentation(label: "已整理", tone: .compiled)
        case "failed":
            InspirationStatusPresentation(label: "整理失败", tone: .failed)
        default:
            InspirationStatusPresentation(label: "待整理", tone: .pending)
        }
    }
}

private struct InspirationTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onSubmit: () -> Void
    let onPasteImages: ([NSImage]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = InspirationNSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? InspirationNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize)
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class InspirationNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onPasteImages: (([NSImage]) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            switch InspirationEditorKeyPolicy.returnAction(for: event.modifierFlags) {
            case .submit:
                onSubmit?()
                return
            case .insertNewline:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let images = InspirationPasteboardImageReader.images(from: .general)
        if !images.isEmpty {
            onPasteImages?(images)
            return
        }
        super.paste(sender)
    }
}

enum InspirationPasteboardImageReader {
    static func images(from pasteboard: NSPasteboard) -> [NSImage] {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            return images
        }

        if let image = imageFromDirectData(in: pasteboard) {
            return [image]
        }

        let htmlImages = imagesFromHTML(in: pasteboard)
        if !htmlImages.isEmpty {
            return htmlImages
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: NSImage.imageTypes
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { object in
            let url: URL?
            if let bridged = object as? URL {
                url = bridged
            } else if let nsURL = object as? NSURL {
                url = nsURL as URL
            } else {
                url = nil
            }
            guard let url else { return nil }
            return NSImage(contentsOf: url)
        }
    }

    private static func imageFromDirectData(in pasteboard: NSPasteboard) -> NSImage? {
        let imageTypes = NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
        let preferredTypes = [
            NSPasteboard.PasteboardType.png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg")
        ]
        let candidateTypes = preferredTypes + imageTypes
        guard let type = pasteboard.availableType(from: candidateTypes),
              let data = pasteboard.data(forType: type) else {
            return nil
        }
        return NSImage(data: data)
    }

    private static func imagesFromHTML(in pasteboard: NSPasteboard) -> [NSImage] {
        let htmlTypes: [NSPasteboard.PasteboardType] = [
            .html,
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("text/html")
        ]
        var seenHTML = Set<String>()
        return htmlTypes
            .compactMap { pasteboard.string(forType: $0) }
            .filter { seenHTML.insert($0).inserted }
            .flatMap(imageSources(in:))
            .compactMap(image(fromHTMLSource:))
    }

    private static func imageSources(in html: String) -> [String] {
        let pattern = #"(?i)<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let sourceRange = Range(match.range(at: 1), in: html) else { return nil }
            return htmlDecoded(String(html[sourceRange]))
        }
    }

    private static func image(fromHTMLSource source: String) -> NSImage? {
        if let dataImage = imageFromDataURL(source) {
            return dataImage
        }
        guard let url = URL(string: source), url.isFileURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func imageFromDataURL(_ source: String) -> NSImage? {
        let lowercased = source.lowercased()
        guard lowercased.hasPrefix("data:image/"),
              let commaIndex = source.firstIndex(of: ",") else {
            return nil
        }
        let metadata = lowercased[..<commaIndex]
        let payload = String(source[source.index(after: commaIndex)...])
        let decodedPayload = payload.removingPercentEncoding ?? payload
        let data: Data?
        if metadata.contains(";base64") {
            data = Data(base64Encoded: decodedPayload, options: .ignoreUnknownCharacters)
        } else {
            data = decodedPayload.data(using: .utf8)
        }
        guard let data else { return nil }
        return NSImage(data: data)
    }

    private static func htmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

private extension Date {
    static func fromInspirationISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
