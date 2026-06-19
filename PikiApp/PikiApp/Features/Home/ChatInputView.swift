import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    @State private var text: String = ""
    @State private var selectedFiles: [URL] = []
    @FocusState private var isFocused: Bool
    let placeholder: String
    let isDisabled: Bool
    let showsStopButton: Bool
    let isStopping: Bool
    let onSend: (String, [URL]) -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedFiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(selectedFiles, id: \.path) { file in
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10))
                            Text(file.lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Button {
                                selectedFiles.removeAll { $0 == file }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.primaryLight)
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: chooseFile) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isDisabled ? Theme.textTertiary : Theme.primary)
                }
                .disabled(isDisabled)
                .buttonStyle(.plain)
                .help("Choose a file")

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...12)
                    .focused($isFocused)
                    .onSubmit {
                        if showsStopButton {
                            onStop()
                        } else {
                            sendIfNotEmpty()
                        }
                    }
                    .disabled(isDisabled)

                if showsStopButton {
                    Button(action: onStop) {
                        Image(systemName: isStopping ? "stop.circle" : "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(isStopping ? Theme.textTertiary : Theme.error)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStopping)
                    .help(isStopping ? "Stopping…" : "Stop current run")
                } else {
                    Button(action: sendIfNotEmpty) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(!canSend ? Theme.textTertiary : Theme.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            isFocused = true
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
