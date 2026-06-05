import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class InboxViewModel {
    var items: [InboxItem] = []
    var selectedFilter: InboxFilter = .all
    var selectedItem: InboxItem?
    var errorMessage: String?
    var statusMessage: String?

    var filteredItems: [InboxItem] {
        switch selectedFilter {
        case .all: items
        case .new: items.filter { $0.status == .new }
        case .processing: items.filter { $0.status == .processing }
        case .completed: items.filter { $0.status == .completed }
        case .failed: items.filter { $0.status == .failed }
        }
    }

    var filterCounts: [InboxFilter: Int] {
        [
            .all: items.count,
            .new: items.filter { $0.status == .new }.count,
            .processing: items.filter { $0.status == .processing }.count,
            .completed: items.filter { $0.status == .completed }.count,
            .failed: items.filter { $0.status == .failed }.count,
        ]
    }

    func handleFileDrop(_ urls: [URL], appState: AppState) {
        guard let first = urls.first else { return }
        ingestPath(first, appState: appState)
    }

    func chooseFiles(appState: AppState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .plainText, .init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .init(filenameExtension: "docx")!]
        if panel.runModal() == .OK, let url = panel.url {
            ingestPath(url, appState: appState)
        }
    }

    private func addDroppedItems(_ urls: [URL]) {
        for url in urls {
            let item = InboxItem(
                id: UUID().uuidString,
                fileName: url.lastPathComponent,
                fileType: InboxItem.fileType(for: url),
                fileSize: InboxItem.fileSize(at: url),
                status: .new,
                addedAt: Date(),
                filePath: url
            )
            items.append(item)
        }
    }

    func loadVaultInbox(vaultURL: URL?) {
        guard let vaultURL else {
            errorMessage = "No vault selected."
            return
        }

        let fileManager = FileManager.default
        let directories = [
            vaultURL.appendingPathComponent("raw/inbox", isDirectory: true),
            vaultURL.appendingPathComponent("raw/sources", isDirectory: true),
        ]

        var loadedItems: [InboxItem] = []
        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls where isRegularFile(url) {
                loadedItems.append(
                    InboxItem(
                        id: url.path(percentEncoded: false),
                        fileName: url.lastPathComponent,
                        fileType: InboxItem.fileType(for: url),
                        fileSize: InboxItem.fileSize(at: url),
                        status: url.path(percentEncoded: false).contains("/raw/sources/") ? .completed : .new,
                        addedAt: modificationDate(for: url),
                        filePath: url
                    )
                )
            }
        }

        items = loadedItems.sorted { $0.addedAt > $1.addedAt }
        if selectedItem == nil {
            selectedItem = items.first
        }
        errorMessage = nil
    }

    func ingest(_ item: InboxItem, appState: AppState) {
        guard let filePath = item.filePath else { return }
        ingestPath(filePath, appState: appState)
    }

    func clear(_ item: InboxItem, appState: AppState) {
        guard let vaultPath = appState.vaultPath,
              let filePath = item.filePath else {
            errorMessage = "No vault or file selected."
            return
        }
        Task {
            do {
                statusMessage = "Clearing..."
                let request = TaskCreateRequest(
                    vaultPath: vaultPath.path(percentEncoded: false),
                    userInput: "清理这个 inbox 文件",
                    selectedPaths: [filePath.path(percentEncoded: false)],
                    mode: "clear-inbox-item"
                )
                _ = try await appState.apiClient.createTask(request)
                loadVaultInbox(vaultURL: vaultPath)
                statusMessage = "Cleared"
            } catch {
                errorMessage = "Clear failed: \(error.localizedDescription)"
                statusMessage = nil
            }
        }
    }

    private func ingestPath(_ url: URL, appState: AppState) {
        guard let vaultPath = appState.vaultPath else {
            errorMessage = "No vault selected."
            return
        }
        addDroppedItems([url])
        Task {
            do {
                statusMessage = "Ingesting..."
                let request = TaskCreateRequest(
                    vaultPath: vaultPath.path(percentEncoded: false),
                    userInput: "请摄入这个文件。",
                    selectedPaths: [url.path(percentEncoded: false)],
                    actionContext: [
                        "action": "ingest_file",
                        "target_path": url.path(percentEncoded: false)
                    ]
                )
                _ = try await appState.apiClient.createTask(request)
                loadVaultInbox(vaultURL: vaultPath)
                statusMessage = "Ingested"
            } catch {
                errorMessage = "Ingest failed: \(error.localizedDescription)"
                statusMessage = nil
            }
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
}

struct InboxItem: Identifiable {
    let id: String
    let fileName: String
    let fileType: FileType
    let fileSize: String
    var status: InboxStatus
    let addedAt: Date
    let filePath: URL?
    var errorMessage: String?

    var canClear: Bool {
        guard let filePath else { return false }
        return filePath.path(percentEncoded: false).contains("/raw/inbox/")
    }

    enum FileType: String {
        case pdf, markdown, docx, text, other

        var icon: String {
            switch self {
            case .pdf: "doc.richtext"
            case .markdown: "doc.text"
            case .docx: "doc.fill"
            case .text: "doc.plaintext"
            case .other: "doc"
            }
        }

        var color: Color {
            switch self {
            case .pdf: .red
            case .markdown: .blue
            case .docx: .indigo
            case .text: .gray
            case .other: .secondary
            }
        }
    }

    static func fileType(for url: URL) -> FileType {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "md", "markdown": .markdown
        case "docx": .docx
        case "txt": .text
        default: .other
        }
    }

    static func fileSize(at url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path()),
              let size = attrs[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum InboxStatus: String {
    case new, processing, completed, failed

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .new: .blue
        case .processing: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

enum InboxFilter: String, CaseIterable {
    case all, new, processing, completed, failed
    var title: String { rawValue.capitalized }
}
