import Foundation
import AppKit

enum HomeSplitMetrics {
    static let chatFraction = 0.6
    static let inspirationFraction = 0.4

    static func paneWidths(for availableWidth: CGFloat) -> (chat: CGFloat, inspiration: CGFloat) {
        let boundedWidth = max(availableWidth, 0)
        let proportionalInspirationWidth = boundedWidth * CGFloat(inspirationFraction)
        let inspirationWidth = min(DetailLayoutGuide.homeAuxiliaryWidth, proportionalInspirationWidth)
        return (
            chat: boundedWidth - inspirationWidth,
            inspiration: inspirationWidth
        )
    }
}

@Observable
@MainActor
final class InspirationViewModel {
    var items: [InspirationDTO] = []
    var searchQuery = ""
    var draftText = ""
    var draftAttachments: [InspirationAttachmentDTO] = []
    var editingId: String?
    var editingText = ""
    var editingAttachments: [InspirationAttachmentDTO] = []
    var isLoading = false
    var isSaving = false
    var isCompiling = false
    var errorMessage: String?
    var statusMessage: String?

    private var loadedVaultPath: String?
    private static let terminalTaskStatuses: Set<String> = [
        "completed",
        "failed",
        "cancelled",
        "input_required",
        "needs_approval"
    ]
    private static let wikiUpdatePollLimit = 120
    private static let wikiUpdatePollIntervalNanoseconds: UInt64 = 1_000_000_000

    func loadIfNeeded(appState: AppState) async {
        let vaultPath = normalizedVaultPath(appState)
        guard vaultPath != loadedVaultPath else { return }
        loadedVaultPath = vaultPath
        await load(appState: appState)
    }

    func load(appState: AppState) async {
        guard appState.isConnected, let vaultPath = normalizedVaultPath(appState) else {
            items = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let loaded = try await appState.runtimeService.listInspirations(
                vaultPath: vaultPath,
                query: query.isEmpty ? nil : query
            )
            items = loaded.sorted(by: Self.sortNewestFirst)
            errorMessage = nil
        } catch {
            errorMessage = "随手记加载失败：\(error.localizedDescription)"
        }
    }

    func submitDraft(appState: AppState) async {
        let content = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let vaultPath = normalizedVaultPath(appState), appState.isConnected else {
            errorMessage = "连接 Runtime 并选择知识库后才能保存随手记。"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let request = InspirationCreateRequest(
                vaultPath: vaultPath,
                content: content,
                attachments: draftAttachments
            )
            let created = try await appState.runtimeService.createInspiration(request)
            upsert(created)
            draftText = ""
            draftAttachments = []
            statusMessage = "已保存"
            errorMessage = nil
        } catch {
            errorMessage = "保存随手记失败：\(error.localizedDescription)"
        }
    }

    func beginEditing(_ item: InspirationDTO) {
        editingId = item.id
        editingText = item.content
        editingAttachments = item.attachments
    }

    func cancelEditing() {
        editingId = nil
        editingText = ""
        editingAttachments = []
    }

    func deleteInspiration(_ item: InspirationDTO, appState: AppState) async {
        guard let vaultPath = normalizedVaultPath(appState), appState.isConnected else {
            errorMessage = "连接 Runtime 并选择知识库后才能删除随手记。"
            return
        }
        do {
            try await appState.runtimeService.deleteInspiration(id: item.id, vaultPath: vaultPath)
            items.removeAll { $0.id == item.id }
            statusMessage = "已删除"
            errorMessage = nil
        } catch {
            errorMessage = "删除随手记失败：\(error.localizedDescription)"
        }
    }

    func saveEditing(appState: AppState) async {
        guard let editingId else { return }
        let content = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let vaultPath = normalizedVaultPath(appState), appState.isConnected else {
            errorMessage = "连接 Runtime 并选择知识库后才能编辑随手记。"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let request = InspirationUpdateRequest(
                vaultPath: vaultPath,
                content: content,
                attachments: editingAttachments
            )
            let updated = try await appState.runtimeService.updateInspiration(id: editingId, request: request)
            upsert(updated)
            cancelEditing()
            statusMessage = "已更新"
            errorMessage = nil
        } catch {
            errorMessage = "更新随手记失败：\(error.localizedDescription)"
        }
    }

    func addDraftImage(_ fileURL: URL, appState: AppState) async {
        await addImage(fileURL, appState: appState, target: .draft)
    }

    func addDraftPastedImage(_ image: NSImage, appState: AppState) async {
        guard let tempURL = savePastedImage(image) else {
            errorMessage = "无法处理粘贴的图片"
            return
        }
        await addImage(tempURL, appState: appState, target: .draft)
    }

    func addEditingImage(_ fileURL: URL, appState: AppState) async {
        await addImage(fileURL, appState: appState, target: .editing)
    }

    func addEditingPastedImage(_ image: NSImage, appState: AppState) async {
        guard let tempURL = savePastedImage(image) else {
            errorMessage = "无法处理粘贴的图片"
            return
        }
        await addImage(tempURL, appState: appState, target: .editing)
    }

    func removeDraftAttachment(_ attachment: InspirationAttachmentDTO) {
        draftAttachments.removeAll { $0 == attachment }
    }

    func removeEditingAttachment(_ attachment: InspirationAttachmentDTO) {
        editingAttachments.removeAll { $0 == attachment }
    }

    func updateWiki(appState: AppState) async {
        guard appState.isConnected, let vaultPath = normalizedVaultPath(appState) else {
            statusMessage = "连接 Runtime 并选择知识库后才能更新 Wiki。"
            return
        }
        guard !isCompiling else { return }
        isCompiling = true
        defer { isCompiling = false }
        do {
            let response = try await appState.runtimeService.compileInspirations(vaultPath: vaultPath)
            if let error = response.error, !error.isEmpty {
                statusMessage = error
                await load(appState: appState)
                return
            }
            if response.compiledCount == 0 {
                await load(appState: appState)
                statusMessage = "没有需要更新的随手记"
                return
            }

            statusMessage = "随手记正在后台整理进 Wiki"
            var terminalTask: TaskRecordDTO?
            if let taskId = response.taskId, !taskId.isEmpty {
                terminalTask = try await waitForWikiUpdateTask(taskId: taskId, appState: appState)
            }
            await load(appState: appState)
            if let terminalTask, terminalTask.status != "completed" {
                let detail = terminalTask.summary ?? terminalTask.status
                statusMessage = "随手记更新未完成：\(detail)"
            } else {
                statusMessage = "随手记已更新到 Wiki"
            }
        } catch {
            statusMessage = "随手记暂未更新：\(error.localizedDescription)"
        }
    }

    private func waitForWikiUpdateTask(taskId: String, appState: AppState) async throws -> TaskRecordDTO {
        var latest: TaskRecordDTO?
        for attempt in 0..<Self.wikiUpdatePollLimit {
            let task = try await appState.runtimeService.getTask(taskId: taskId)
            latest = task
            if Self.terminalTaskStatuses.contains(task.status) {
                return task
            }
            if attempt < Self.wikiUpdatePollLimit - 1 {
                try await Task.sleep(nanoseconds: Self.wikiUpdatePollIntervalNanoseconds)
            }
        }
        return latest ?? TaskRecordDTO(id: taskId, status: "running", summary: nil, output: nil)
    }

    private enum AttachmentTarget {
        case draft
        case editing
    }

    private func addImage(_ fileURL: URL, appState: AppState, target: AttachmentTarget) async {
        guard appState.isConnected else {
            errorMessage = "连接 Runtime 后才能上传图片。"
            return
        }
        do {
            let uploaded = try await appState.runtimeService.uploadFile(fileURL)
            let attachment = InspirationAttachmentDTO(
                filename: uploaded.filename,
                bufferedPath: uploaded.bufferedPath,
                mimeType: Self.mimeType(for: fileURL),
                sizeBytes: uploaded.sizeBytes
            )
            switch target {
            case .draft:
                draftAttachments.append(attachment)
            case .editing:
                editingAttachments.append(attachment)
            }
            errorMessage = nil
        } catch {
            errorMessage = "图片上传失败：\(error.localizedDescription)"
        }
    }

    private func upsert(_ item: InspirationDTO) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        items.sort(by: Self.sortNewestFirst)
    }

    private static func sortNewestFirst(_ lhs: InspirationDTO, _ rhs: InspirationDTO) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id > rhs.id
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    private func normalizedVaultPath(_ appState: AppState) -> String? {
        guard let path = appState.vaultPath?.path(percentEncoded: false) else { return nil }
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func savePastedImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let filename = "paste-\(UUID().uuidString.prefix(8)).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try png.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
