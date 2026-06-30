import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class InboxViewModel {
    var items: [InboxItem] = []
    var selectedDirectoryFilter: InboxDirectoryFilter = .all
    var selectedFileTypeFilter: InboxFileTypeFilter = .all
    var selectedItem: InboxItem?
    var errorMessage: String?
    var statusMessage: String?
    var isLoading = false
    var searchQuery: String = ""

    private var loadedVaultPath: String?

    var filteredItems: [InboxItem] {
        let filterByDirectory: [InboxItem] = switch selectedDirectoryFilter {
        case .all: items
        case .staging, .source, .asset:
            items.filter { $0.directoryCategory == selectedDirectoryFilter.directoryCategory }
        }

        let filterByType: [InboxItem] = switch selectedFileTypeFilter {
        case .all: filterByDirectory
        case .pdf, .markdown, .docx, .text, .other:
            filterByDirectory.filter { $0.fileType == selectedFileTypeFilter.fileType }
        }

        if searchQuery.isEmpty {
            return filterByType
        }

        return filterByType.filter { item in
            item.fileName.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var directoryCounts: [InboxDirectoryFilter: Int] {
        [
            .all: items.count,
            .staging: items.filter { $0.directoryCategory == .staging }.count,
            .source: items.filter { $0.directoryCategory == .source }.count,
            .asset: items.filter { $0.directoryCategory == .asset }.count,
        ]
    }

    var fileTypeCounts: [InboxFileTypeFilter: Int] {
        [
            .all: items.count,
            .pdf: items.filter { $0.fileType == .pdf }.count,
            .markdown: items.filter { $0.fileType == .markdown }.count,
            .docx: items.filter { $0.fileType == .docx }.count,
            .text: items.filter { $0.fileType == .text }.count,
            .other: items.filter { $0.fileType == .other }.count,
        ]
    }

    func handleFileDrop(_ urls: [URL], appState: AppState) {
        guard let first = urls.first else { return }
        importFiles([first], appState: appState)
    }

    func chooseFiles(appState: AppState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .plainText, .init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .init(filenameExtension: "docx")!]
        if panel.runModal() == .OK, let url = panel.url {
            importFiles([url], appState: appState)
        }
    }

    private func importFiles(_ urls: [URL], appState: AppState) {
        guard let vaultURL = appState.vaultPath else {
            errorMessage = "未选择知识库。"
            return
        }

        statusMessage = "正在导入文件..."
        errorMessage = nil

        do {
            let importedItems = try urls.map { url in
                let copiedURL = try Self.copyIntoRawInbox(sourceURL: url, vaultURL: vaultURL)
                return InboxItem(
                    id: copiedURL.path(percentEncoded: false),
                    fileName: copiedURL.lastPathComponent,
                    fileType: InboxItem.fileType(for: copiedURL),
                    fileSize: InboxItem.fileSize(at: copiedURL),
                    directoryCategory: .staging,
                    status: .new,
                    addedAt: Date(),
                    filePath: copiedURL
                )
            }
            items.append(contentsOf: importedItems)
            items.sort { $0.addedAt > $1.addedAt }
            selectedItem = importedItems.last ?? items.first
            statusMessage = "已导入到 raw/inbox"
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private nonisolated static func copyIntoRawInbox(sourceURL: URL, vaultURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let inboxURL = vaultURL.appendingPathComponent("raw/inbox", isDirectory: true)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let destinationURL = uniqueInboxDestination(for: sourceURL.lastPathComponent, inboxURL: inboxURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private nonisolated static func uniqueInboxDestination(for fileName: String, inboxURL: URL) -> URL {
        let candidateURL = inboxURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: candidateURL.path) else {
            return candidateURL
        }

        let sourceURL = URL(fileURLWithPath: fileName)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        var index = 2
        while true {
            let suffix = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let dedupedURL = inboxURL.appendingPathComponent(suffix)
            if !fileManager.fileExists(atPath: dedupedURL.path) {
                return dedupedURL
            }
            index += 1
        }
    }

    private func addDroppedItems(_ urls: [URL]) {
        for url in urls {
            let item = InboxItem(
                id: UUID().uuidString,
                fileName: url.lastPathComponent,
                fileType: InboxItem.fileType(for: url),
                fileSize: InboxItem.fileSize(at: url),
                directoryCategory: .staging,
                status: .new,
                addedAt: Date(),
                filePath: url
            )
            items.append(item)
        }
    }

    func loadIfNeeded(vaultURL: URL?) async {
        let path = vaultURL?.path(percentEncoded: false)
        guard path != loadedVaultPath else { return }
        loadedVaultPath = path
        await loadVaultInbox(vaultURL: vaultURL)
    }

    func loadVaultInbox(vaultURL: URL?) async {
        guard let vaultURL else {
            errorMessage = "未选择知识库。"
            return
        }

        isLoading = true
        let loaded = await Task.detached {
            Self.scanDirectories(vaultURL: vaultURL)
        }.value

        guard !Task.isCancelled else {
            loadedVaultPath = nil
            isLoading = false
            return
        }

        items = loaded
        if selectedItem == nil {
            selectedItem = items.first
        }
        errorMessage = nil
        isLoading = false
    }

    private nonisolated static func scanDirectories(vaultURL: URL) -> [InboxItem] {
        let fileManager = FileManager.default
        let directories = [
            ScannedDirectory(
                category: .staging,
                url: vaultURL.appendingPathComponent("raw/inbox", isDirectory: true)
            ),
            ScannedDirectory(
                category: .source,
                url: vaultURL.appendingPathComponent("raw/sources", isDirectory: true)
            ),
            ScannedDirectory(
                category: .asset,
                url: vaultURL.appendingPathComponent("raw/assets", isDirectory: true)
            ),
        ]

        var loadedItems: [InboxItem] = []
        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory.url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls.flatMap({ scannedURLs(in: $0, category: directory.category) }) where isRegularFile(url) {
                loadedItems.append(
                    InboxItem(
                        id: url.path(percentEncoded: false),
                        fileName: url.lastPathComponent,
                        fileType: InboxItem.fileType(for: url),
                        fileSize: InboxItem.fileSize(at: url),
                        directoryCategory: directory.category,
                        status: directory.category == .source ? .completed : .new,
                        addedAt: modificationDate(for: url),
                        filePath: url
                    )
                )
            }
        }

        return loadedItems.sorted { $0.addedAt > $1.addedAt }
    }

    func clear(_ item: InboxItem, appState: AppState) {
        guard let vaultPath = appState.vaultPath,
              let filePath = item.filePath else {
            errorMessage = "未选择知识库或文件。"
            return
        }
        Task {
            do {
                statusMessage = "正在清除..."
                let request = TaskCreateRequest(
                    vaultPath: vaultPath.path(percentEncoded: false),
                    userInput: "清理这个 inbox 文件",
                    selectedPaths: [filePath.path(percentEncoded: false)],
                    mode: "clear-inbox-item"
                )
                _ = try await appState.runtimeService.createTask(request)
                await loadVaultInbox(vaultURL: vaultPath)
                statusMessage = "已清除"
            } catch {
                errorMessage = "清除失败: \(error.localizedDescription)"
                statusMessage = nil
            }
        }
    }

    private nonisolated static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private nonisolated static func scannedURLs(in url: URL, category: InboxDirectoryCategory) -> [URL] {
        switch category {
        case .asset:
            if isRegularFile(url) {
                return [url]
            }
            guard let nestedURLs = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return nestedURLs.filter { isRegularFile($0) }
        case .staging, .source:
            return [url]
        }
    }

    private nonisolated static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
}

private struct ScannedDirectory {
    let category: InboxDirectoryCategory
    let url: URL
}

struct InboxItem: Identifiable {
    let id: String
    let fileName: String
    let fileType: FileType
    let fileSize: String
    let directoryCategory: InboxDirectoryCategory
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

enum InboxDirectoryCategory: String {
    case staging
    case source
    case asset

    var title: String {
        switch self {
        case .staging: "原资料"
        case .source: "来源页"
        case .asset: "附件库"
        }
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

enum InboxDirectoryFilter: CaseIterable {
    case all
    case staging
    case source
    case asset

    var title: String {
        switch self {
        case .all: "全部"
        case .staging: "原资料"
        case .source: "来源页"
        case .asset: "附件库"
        }
    }

    var directoryCategory: InboxDirectoryCategory? {
        switch self {
        case .all: nil
        case .staging: .staging
        case .source: .source
        case .asset: .asset
        }
    }
}

enum InboxFileTypeFilter: CaseIterable {
    case all
    case pdf
    case markdown
    case docx
    case text
    case other

    var title: String {
        switch self {
        case .all: "全部类型"
        case .pdf: "PDF"
        case .markdown: "Markdown"
        case .docx: "DOCX"
        case .text: "文字"
        case .other: "其他"
        }
    }

    var fileType: InboxItem.FileType? {
        switch self {
        case .all: nil
        case .pdf: .pdf
        case .markdown: .markdown
        case .docx: .docx
        case .text: .text
        case .other: .other
        }
    }
}
