import SwiftUI
import UniformTypeIdentifiers

enum ChatInputStyle {
    case hero
    case docked
}

enum ChatInputExternalRequest: Equatable {
    case openLocalFilePicker
}

enum ChatInputAttachmentMenuAction: Equatable {
    case localFileUpload
    case podcastTranscription
}

struct ChatInputAttachmentMenuState: Equatable {
    var isExpanded = false

    mutating func toggle() {
        isExpanded.toggle()
    }

    mutating func dismiss() -> ChatInputAttachmentMenuAction? {
        isExpanded = false
        return nil
    }

    mutating func select(_ action: ChatInputAttachmentMenuAction) -> ChatInputAttachmentMenuAction {
        isExpanded = false
        return action
    }
}

struct ChatInputMetrics {
    let style: ChatInputStyle

    var usesFullscreenDismissOverlay: Bool {
        false
    }

    var minHeight: CGFloat {
        style == .hero ? 82 : 0
    }

    var horizontalPadding: CGFloat {
        style == .hero ? 20 : 16
    }

    var verticalPadding: CGFloat {
        style == .hero ? 16 : 16
    }

    var cornerRadius: CGFloat {
        style == .hero ? 24 : 18
    }

    var textSize: CGFloat {
        style == .hero ? 17 : 13
    }

    var helperTextSize: CGFloat {
        style == .hero ? 12 : 11
    }

    var chipTextSize: CGFloat {
        style == .hero ? 12 : 11
    }

    var chipIconSize: CGFloat {
        style == .hero ? 10 : 10
    }

    var chipHorizontalPadding: CGFloat {
        style == .hero ? 9 : 8
    }

    var chipVerticalPadding: CGFloat {
        style == .hero ? 4 : 4
    }

    var actionButtonSize: CGFloat {
        style == .hero ? 34 : 28
    }

    var attachmentIconSize: CGFloat {
        style == .hero ? 18 : 20
    }

    var sendIconSize: CGFloat {
        style == .hero ? 20 : 24
    }

    var attachmentSymbolName: String {
        "plus.circle.fill"
    }

    var sendSymbolName: String {
        "arrow.up.circle.fill"
    }
}

struct ChatInputView: View {
    @Binding var text: String
    @State private var selectedFiles: [URL] = []
    @State private var attachmentMenuState = ChatInputAttachmentMenuState()
    @FocusState private var isFocused: Bool
    let placeholder: String
    let isDisabled: Bool
    let showsStopButton: Bool
    let isStopping: Bool
    let style: ChatInputStyle
    let helperText: String?
    let autofocus: Bool
    let externalRequest: ChatInputExternalRequest?
    let onExternalRequestHandled: (() -> Void)?
    let onRequestFileUpload: (() -> Void)?
    let onRequestPodcastPrompt: (() -> Void)?
    let onSend: (String, [URL]) -> Void
    let onStop: () -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        isDisabled: Bool,
        showsStopButton: Bool,
        isStopping: Bool,
        style: ChatInputStyle,
        helperText: String?,
        autofocus: Bool,
        externalRequest: ChatInputExternalRequest?,
        onExternalRequestHandled: (() -> Void)?,
        onRequestFileUpload: (() -> Void)?,
        onRequestPodcastPrompt: (() -> Void)?,
        onSend: @escaping (String, [URL]) -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.showsStopButton = showsStopButton
        self.isStopping = isStopping
        self.style = style
        self.helperText = helperText
        self.autofocus = autofocus
        self.externalRequest = externalRequest
        self.onExternalRequestHandled = onExternalRequestHandled
        self.onRequestFileUpload = onRequestFileUpload
        self.onRequestPodcastPrompt = onRequestPodcastPrompt
        self.onSend = onSend
        self.onStop = onStop
    }

    private var metrics: ChatInputMetrics {
        ChatInputMetrics(style: style)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if attachmentMenuState.isExpanded {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        _ = attachmentMenuState.dismiss()
                    }
            }

            VStack(alignment: .leading, spacing: style == .hero ? 14 : 8) {
                if !selectedFiles.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(selectedFiles, id: \.path) { file in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: chipIconSize))
                                Text(file.lastPathComponent)
                                    .font(.system(size: chipTextSize))
                                    .lineLimit(1)
                                Button {
                                    selectedFiles.removeAll { $0 == file }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: chipIconSize))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, chipHorizontalPadding)
                            .padding(.vertical, chipVerticalPadding)
                            .background(Theme.subtleFill)
                            .clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: textSize))
                    .lineLimit(style == .hero ? 1...8 : 1...12)
                    .focused($isFocused)
                    .onSubmit {
                        if showsStopButton {
                            onStop()
                        } else {
                            sendIfNotEmpty()
                        }
                    }
                    .disabled(isDisabled)

                if let helperText, !helperText.isEmpty {
                    Text(helperText)
                        .font(.system(size: helperTextSize))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .padding(.top, style == .hero ? 2 : 0)
                }

                HStack(spacing: style == .hero ? 14 : 12) {
                    Button(action: chooseFile) {
                        Image(systemName: metrics.attachmentSymbolName)
                            .font(.system(size: metrics.attachmentIconSize, weight: .regular))
                            .foregroundStyle(attachmentTint)
                            .frame(width: metrics.actionButtonSize, height: metrics.actionButtonSize)
                            .background(
                                Circle()
                                    .fill(attachmentBackground)
                            )
                    }
                    .disabled(isDisabled)
                    .buttonStyle(.plain)
                    .help("Choose a file")
                    .overlay(alignment: .topLeading) {
                        if attachmentMenuState.isExpanded {
                            ChatInputAttachmentMenuBubble(
                                style: style,
                                onSelect: handleAttachmentMenuSelection
                            )
                            .offset(x: -6, y: -attachmentMenuVerticalOffset)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.96, anchor: .bottomLeading)
                                        .combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    if showsStopButton {
                        Button(action: onStop) {
                            Image(systemName: isStopping ? "stop.circle" : "stop.circle.fill")
                                .font(.system(size: sendIconSize))
                                .foregroundStyle(isStopping ? Theme.textTertiary : Theme.error)
                        }
                        .buttonStyle(.plain)
                        .disabled(isStopping)
                        .help(isStopping ? "Stopping…" : "Stop current run")
                    } else {
                        Button(action: sendIfNotEmpty) {
                            Image(systemName: metrics.sendSymbolName)
                                .font(.system(size: metrics.sendIconSize))
                                .foregroundStyle(sendIconTint)
                                .frame(width: metrics.actionButtonSize, height: metrics.actionButtonSize)
                                .background(
                                    Circle()
                                        .fill(sendButtonBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .fill(Theme.elevatedCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.cornerRadius)
                            .stroke(style == .hero ? Theme.border.opacity(0.8) : Theme.border.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(style == .hero ? 0.08 : 0.06), radius: style == .hero ? 16 : 4, x: 0, y: style == .hero ? 8 : 2)
            )
            .zIndex(1)
        }
        .clipped()
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: attachmentMenuState.isExpanded)
        .onAppear {
            isFocused = autofocus
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            Task {
                await addFiles(from: providers)
            }
        }
        .onChange(of: externalRequest) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case .openLocalFilePicker:
                presentFilePanel()
            }
            onExternalRequestHandled?()
        }
    }

    private var canSend: Bool {
        guard !isDisabled else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedFiles.isEmpty
    }

    private var minHeight: CGFloat {
        metrics.minHeight
    }

    private var horizontalPadding: CGFloat {
        metrics.horizontalPadding
    }

    private var verticalPadding: CGFloat {
        metrics.verticalPadding
    }

    private var cornerRadius: CGFloat {
        metrics.cornerRadius
    }

    private var textSize: CGFloat {
        metrics.textSize
    }

    private var helperTextSize: CGFloat {
        metrics.helperTextSize
    }

    private var chipTextSize: CGFloat {
        metrics.chipTextSize
    }

    private var chipIconSize: CGFloat {
        metrics.chipIconSize
    }

    private var chipHorizontalPadding: CGFloat {
        metrics.chipHorizontalPadding
    }

    private var chipVerticalPadding: CGFloat {
        metrics.chipVerticalPadding
    }

    private var actionButtonSize: CGFloat {
        metrics.actionButtonSize
    }

    private var attachmentIconSize: CGFloat {
        metrics.attachmentIconSize
    }

    private var sendIconSize: CGFloat {
        metrics.sendIconSize
    }

    private var attachmentMenuVerticalOffset: CGFloat {
        style == .hero ? 110 : 102
    }

    private var attachmentTint: Color {
        isDisabled ? Theme.textTertiary : Theme.textPrimary
    }

    private var attachmentBackground: Color {
        style == .hero ? .clear : .clear
    }

    private var sendButtonBackground: Color {
        if showsStopButton {
            return .clear
        }
        return canSend ? Theme.accent : Theme.selection
    }

    private var sendIconTint: Color {
        if style == .hero {
            return canSend ? .white : Theme.textTertiary
        }
        return !canSend ? Theme.textTertiary : Theme.accent
    }

    private func sendIfNotEmpty() {
        guard !isDisabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !selectedFiles.isEmpty else { return }
        onSend(trimmed, selectedFiles)
        text = ""
        selectedFiles = []
    }

    private func chooseFile() {
        attachmentMenuState.toggle()
    }

    private func handleAttachmentMenuSelection(_ action: ChatInputAttachmentMenuAction) {
        switch attachmentMenuState.select(action) {
        case .localFileUpload:
            if let onRequestFileUpload {
                onRequestFileUpload()
            } else {
                presentFilePanel()
            }
        case .podcastTranscription:
            onRequestPodcastPrompt?()
        }
    }

    private func presentFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .plainText, UTType(filenameExtension: "md")!, UTType(filenameExtension: "markdown")!, UTType(filenameExtension: "docx")!]
        if panel.runModal() == .OK, let url = panel.url {
            selectedFiles = [url]
        }
    }

    @MainActor
    private func addFiles(from providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
               let url = fileURL(from: item) {
                urls.append(url)
            }
        }
        if let first = urls.first {
            selectedFiles = [first]
        }
    }

    private func fileURL(from item: NSSecureCoding) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return URL(string: value)
        }
        if let value = item as? String {
            return URL(string: value)
        }
        return nil
    }
}

private struct ChatInputAttachmentMenuBubble: View {
    let style: ChatInputStyle
    let onSelect: (ChatInputAttachmentMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                ChatInputAttachmentMenuOptionRow(
                    icon: "doc.badge.plus",
                    title: "上传本地文件",
                    subtitle: "选择文档或笔记素材"
                ) {
                    onSelect(.localFileUpload)
                }

                Divider()
                    .padding(.horizontal, 12)

                ChatInputAttachmentMenuOptionRow(
                    icon: "waveform.badge.mic",
                    title: "上传播客-自动转录",
                    subtitle: "生成可继续整理的文本"
                ) {
                    onSelect(.podcastTranscription)
                }
            }
            .padding(.vertical, 6)

            ChatInputAttachmentMenuPointer()
                .fill(Theme.elevatedCardBackground)
                .frame(width: 16, height: 10)
                .overlay {
                    ChatInputAttachmentMenuPointer()
                        .stroke(Theme.border.opacity(0.9), lineWidth: 1)
                }
                .padding(.leading, style == .hero ? 18 : 16)
                .offset(y: 0.5)
        }
        .frame(width: style == .hero ? 224 : 214)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.elevatedCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.border.opacity(0.95), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: style == .hero ? 18 : 12, x: 0, y: 8)
        )
    }
}

private struct ChatInputAttachmentMenuOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.subtleFill)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatInputAttachmentMenuPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
