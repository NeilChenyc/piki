import SwiftUI

struct FilePreviewPanel: View {
    let item: InboxItem
    let onIngest: () -> Void
    let onClear: () -> Void

    @State private var previewText: String = ""
    @State private var previewKind: PreviewKind = .plain
    @State private var previewBaseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 8) {
                        Text(item.fileType.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(item.fileType.color)
                            .background(item.fileType.color.opacity(0.1))
                            .clipShape(.capsule)
                        Text(item.fileSize)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }

            Divider()

            ScrollView {
                if previewText.isEmpty {
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if previewKind == .markdown {
                    MarkdownTextView(previewText, baseURL: previewBaseURL)
                } else {
                    Text(previewText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Ingest", action: onIngest)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
                    .disabled(!item.canClear)
            }
        }
        .padding(16)
        .task(id: item.id) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard let filePath = item.filePath else {
            previewKind = .plain
            previewBaseURL = nil
            previewText = "No preview available"
            return
        }
        let fileExtension = filePath.pathExtension.lowercased()
        guard ["md", "markdown", "txt"].contains(fileExtension) else {
            previewKind = .plain
            previewBaseURL = nil
            previewText = "Preview is available for Markdown and text files."
            return
        }
        previewKind = ["md", "markdown"].contains(fileExtension) ? .markdown : .plain
        previewBaseURL = previewKind == .markdown ? filePath.deletingLastPathComponent() : nil
        let url = filePath
        let content = await Task.detached {
            (try? String(contentsOf: url, encoding: .utf8)) ?? "Unable to read preview."
        }.value
        previewText = content
    }
}

private enum PreviewKind {
    case markdown
    case plain
}
