import SwiftUI

struct FilePreviewPanel: View {
    let item: InboxItem
    let onIngest: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
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

            // Preview content placeholder
            ScrollView {
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(previewText.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            // Action buttons
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
    }

    private var previewText: String {
        guard let filePath = item.filePath else {
            return "No preview available"
        }
        guard ["md", "markdown", "txt"].contains(filePath.pathExtension.lowercased()) else {
            return "Preview is available for Markdown and text files."
        }
        return (try? String(contentsOf: filePath, encoding: .utf8)) ?? "Unable to read preview."
    }
}
