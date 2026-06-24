import SwiftUI
import UniformTypeIdentifiers

enum ChatInputStyle {
    case hero
    case docked
}

struct ChatInputView: View {
    @State private var text: String = ""
    @State private var selectedFiles: [URL] = []
    @FocusState private var isFocused: Bool
    let placeholder: String
    let isDisabled: Bool
    let showsStopButton: Bool
    let isStopping: Bool
    let style: ChatInputStyle
    let helperText: String?
    let autofocus: Bool
    let onSend: (String, [URL]) -> Void
    let onStop: () -> Void

    var body: some View {
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
                        .background(Theme.surfaceSecondary)
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
                    Image(systemName: style == .hero ? "paperclip" : "plus.circle.fill")
                        .font(.system(size: attachmentIconSize, weight: style == .hero ? .semibold : .regular))
                        .foregroundStyle(attachmentTint)
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .background(
                            Circle()
                                .fill(attachmentBackground)
                        )
                }
                .disabled(isDisabled)
                .buttonStyle(.plain)
                .help("Choose a file")

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
                        Image(systemName: style == .hero ? "paperplane.fill" : "arrow.up.circle.fill")
                            .font(.system(size: sendIconSize))
                            .foregroundStyle(sendIconTint)
                            .frame(width: actionButtonSize, height: actionButtonSize)
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
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(style == .hero ? Theme.border.opacity(0.8) : Theme.border.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(style == .hero ? 0.08 : 0.06), radius: style == .hero ? 16 : 4, x: 0, y: style == .hero ? 8 : 2)
        )
        .onAppear {
            isFocused = autofocus
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            Task {
                await addFiles(from: providers)
            }
        }
    }

    private var canSend: Bool {
        guard !isDisabled else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedFiles.isEmpty
    }

    private var minHeight: CGFloat {
        style == .hero ? 232 : 0
    }

    private var horizontalPadding: CGFloat {
        style == .hero ? 24 : 16
    }

    private var verticalPadding: CGFloat {
        style == .hero ? 22 : 16
    }

    private var cornerRadius: CGFloat {
        style == .hero ? 28 : 18
    }

    private var textSize: CGFloat {
        style == .hero ? 21 : 13
    }

    private var helperTextSize: CGFloat {
        style == .hero ? 12 : 11
    }

    private var chipTextSize: CGFloat {
        style == .hero ? 13 : 11
    }

    private var chipIconSize: CGFloat {
        style == .hero ? 11 : 10
    }

    private var chipHorizontalPadding: CGFloat {
        style == .hero ? 10 : 8
    }

    private var chipVerticalPadding: CGFloat {
        style == .hero ? 5 : 4
    }

    private var actionButtonSize: CGFloat {
        style == .hero ? 42 : 28
    }

    private var attachmentIconSize: CGFloat {
        style == .hero ? 22 : 20
    }

    private var sendIconSize: CGFloat {
        style == .hero ? 18 : 24
    }

    private var attachmentTint: Color {
        isDisabled ? Theme.textTertiary : Theme.textPrimary
    }

    private var attachmentBackground: Color {
        style == .hero ? Theme.surfaceSecondary : .clear
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
