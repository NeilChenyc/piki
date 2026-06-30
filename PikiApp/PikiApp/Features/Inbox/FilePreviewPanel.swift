import SwiftUI

struct FilePreviewPanel: View {
    let item: InboxItem
    let onIngest: () -> Void
    let onClear: () -> Void

    @State private var previewText: String = ""
    @State private var previewKind: PreviewKind = .plain
    @State private var previewBaseURL: URL?
    @State private var pdfURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 8) {
                        Text(item.directoryCategory.title)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Theme.textSecondary)
                            .background(Theme.primaryPanelBackground)
                            .clipShape(.capsule)
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

            Group {
                if previewKind == .pdf, let pdfURL {
                    PDFPreviewView(url: pdfURL)
                } else if previewText.isEmpty {
                    Text("正在加载...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if previewKind == .markdown {
                    DocumentMarkdownView(
                        previewText,
                        presentationMode: .documentPage(displayTitle: nil),
                        baseURL: previewBaseURL
                    )
                } else {
                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer()

            HStack(spacing: 12) {
                Button("摄入", action: onIngest)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                Button("清除", action: onClear)
                    .buttonStyle(.bordered)
                    .disabled(!item.canClear)
            }
        }
        .padding(16)
        .background(Theme.secondaryPanelBackground)
        .task(id: item.id) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard let filePath = item.filePath else {
            previewKind = .plain
            previewBaseURL = nil
            pdfURL = nil
            previewText = "暂无预览"
            return
        }
        let fileExtension = filePath.pathExtension.lowercased()

        if fileExtension == "pdf" {
            previewKind = .pdf
            pdfURL = filePath
            previewText = ""
            return
        }

        guard ["md", "markdown", "txt"].contains(fileExtension) else {
            previewKind = .plain
            previewBaseURL = nil
            pdfURL = nil
            previewText = "预览仅支持 PDF、Markdown 和文本文件。"
            return
        }
        previewKind = ["md", "markdown"].contains(fileExtension) ? .markdown : .plain
        previewBaseURL = previewKind == .markdown ? filePath.deletingLastPathComponent() : nil
        pdfURL = nil
        let url = filePath
        let content = await Task.detached {
            (try? String(contentsOf: url, encoding: .utf8)) ?? "无法读取预览。"
        }.value
        previewText = content
    }
}

import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
    }
}

private enum PreviewKind {
    case markdown
    case plain
    case pdf
}
