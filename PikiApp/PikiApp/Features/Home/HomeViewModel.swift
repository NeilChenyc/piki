import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var messages: [ChatMessage] = []
    var recentActivity: [ActivityEntry] = []
    var inputText: String = ""
    var isSending = false
    var statusText: String?
    private var conversationId = UUID().uuidString

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    func sendMessage(_ text: String, appState: AppState, selectedFiles: [URL] = []) {
        guard appState.isConnected else {
            appendSystemMessage(appState.serviceErrorMessage ?? "Agent Service is disconnected.")
            return
        }
        guard let vaultPath = appState.vaultPath else {
            appendSystemMessage("Select a vault before sending a message.")
            return
        }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: messageText(text, selectedFiles: selectedFiles),
            timestamp: Date()
        )
        messages.append(userMessage)

        let assistantMessageId = UUID().uuidString
        messages.append(
            ChatMessage(
                id: assistantMessageId,
                role: .assistant,
                content: "",
                timestamp: Date()
            )
        )
        isSending = true
        statusText = "Creating task..."

        Task {
            await runTask(
                text,
                selectedFiles: selectedFiles,
                vaultPath: vaultPath,
                appState: appState,
                assistantMessageId: assistantMessageId
            )
        }
    }

    func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .ask:
            break
        case .ingest:
            break
        case .healthCheck:
            break
        }
    }

    private func runTask(
        _ text: String,
        selectedFiles: [URL],
        vaultPath: URL,
        appState: AppState,
        assistantMessageId: String
    ) async {
        do {
            let request = TaskCreateRequest(
                vaultPath: vaultPath.path(percentEncoded: false),
                userInput: text.isEmpty ? "请摄入这个文件。" : text,
                selectedPaths: selectedFiles.map { $0.path(percentEncoded: false) },
                conversationId: conversationId,
                asyncMode: true
            )
            let response = try await appState.apiClient.createTask(request)
            statusText = "正在理解请求"

            var finalEventContent: String?
            for try await event in appState.apiClient.taskEvents(taskId: response.taskId) {
                if let content = handle(event, assistantMessageId: assistantMessageId) {
                    finalEventContent = content
                }
            }

            let task = try await appState.apiClient.getTask(taskId: response.taskId)
            let content = task.output?.answer
                ?? task.output?.summary
                ?? task.summary
                ?? finalEventContent
                ?? "Task finished without a final message."
            updateMessage(id: assistantMessageId, content: content)
            await loadRecentJournal(appState: appState)
            statusText = nil
        } catch {
            updateMessage(id: assistantMessageId, content: "Task failed: \(error.localizedDescription)")
            statusText = nil
        }
        isSending = false
    }

    func loadRecentJournal(appState: AppState) async {
        guard appState.isConnected, let vaultPath = appState.vaultPath else { return }
        do {
            let entries = try await appState.apiClient.recentJournal(
                limit: 10,
                vaultPath: vaultPath.path(percentEncoded: false)
            )
            recentActivity = entries.map(ActivityEntry.init(journalEntry:))
        } catch {
            statusText = "Unable to load Change Journal: \(error.localizedDescription)"
        }
    }

    func rollback(_ entry: ActivityEntry, appState: AppState) {
        guard let journalId = entry.journalId else { return }
        Task {
            do {
                statusText = "正在回退变更"
                try await appState.apiClient.rollback(entryId: journalId)
                await loadRecentJournal(appState: appState)
                statusText = nil
            } catch {
                statusText = "Rollback failed: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func handle(_ event: TaskEvent, assistantMessageId: String) -> String? {
        switch event.type {
        case "agent.progress":
            if let title = event.payload.title {
                appendProgressStep(
                    messageId: assistantMessageId,
                    title: title,
                    detail: event.payload.detail,
                    stage: event.payload.stage
                )
                if let detail = event.payload.detail, !detail.isEmpty {
                    statusText = "\(title) · \(detail)"
                } else {
                    statusText = title
                }
            }
            return nil
        case "message.delta":
            if let delta = event.payload.delta, !delta.isEmpty {
                appendMessageDelta(id: assistantMessageId, delta: delta)
                statusText = "正在生成回答"
            }
            return nil
        case "task.completed":
            let content = event.payload.answer
                ?? event.payload.summary
                ?? event.payload.content
                ?? "Task completed."
            statusText = "已完成"
            return content
        case "task.failed":
            updateMessage(
                id: assistantMessageId,
                content: event.payload.error ?? event.payload.summary ?? "Task failed."
            )
            statusText = nil
            return event.payload.error ?? event.payload.summary
        case "sdk.run.completed":
            statusText = "正在整理回答"
            return nil
        case "sdk.run.started":
            return nil
        default:
            if event.type.hasSuffix(".started") {
                statusText = friendlyStatus(for: event.type)
            }
            return nil
        }
    }

    private func friendlyStatus(for eventType: String) -> String {
        switch eventType {
        case "source_intake.started": "正在整理资料"
        case "ingest.started", "ingest_queue.process_started": "正在整理资料"
        case "sdk.run.started": "正在思考和生成"
        case "rollback.completed", "rollback.failed": "正在回退变更"
        default: "正在处理"
        }
    }

    private func updateMessage(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func appendMessageDelta(id: String, delta: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func appendProgressStep(messageId: String, title: String, detail: String?, stage: String?) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        if messages[index].progressSteps.last?.title == title,
           messages[index].progressSteps.last?.detail == detail {
            return
        }
        messages[index].progressSteps.append(
            ChatProgressStep(
                title: title,
                detail: detail ?? "",
                stage: stage ?? ""
            )
        )
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(
            ChatMessage(
                id: UUID().uuidString,
                role: .system,
                content: content,
                timestamp: Date()
            )
        )
    }

    private func messageText(_ text: String, selectedFiles: [URL]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedFiles.isEmpty else { return trimmed }
        let names = selectedFiles.map(\.lastPathComponent).joined(separator: ", ")
        if trimmed.isEmpty {
            return "Attached: \(names)"
        }
        return "\(trimmed)\n\nAttached: \(names)"
    }
}

struct ChatMessage: Identifiable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var citations: [Citation] = []
    var progressSteps: [ChatProgressStep] = []

    enum MessageRole {
        case user, assistant, system
    }
}

struct ChatProgressStep: Identifiable {
    let id = UUID().uuidString
    let title: String
    let detail: String
    let stage: String
}

struct Citation: Identifiable {
    let id: String
    let pageTitle: String
    let pagePath: String
}

struct ActivityEntry: Identifiable {
    let id: String
    let description: String
    let timestamp: Date
    let type: ActivityType
    let journalId: String?
    let affectedFiles: [String]
    let status: String
    let canRollback: Bool

    init(
        id: String,
        description: String,
        timestamp: Date,
        type: ActivityType,
        journalId: String? = nil,
        affectedFiles: [String] = [],
        status: String = "",
        canRollback: Bool = false
    ) {
        self.id = id
        self.description = description
        self.timestamp = timestamp
        self.type = type
        self.journalId = journalId
        self.affectedFiles = affectedFiles
        self.status = status
        self.canRollback = canRollback
    }

    init(journalEntry: JournalEntry) {
        id = journalEntry.id
        journalId = journalEntry.id
        affectedFiles = journalEntry.affectedFiles
        status = journalEntry.status
        canRollback = journalEntry.eligibleForRollback
        timestamp = Date.fromISO8601(journalEntry.createdAt) ?? Date()
        type = journalEntry.status == "rolled_back" ? .rollback : .ingest
        if journalEntry.affectedFiles.isEmpty {
            description = "Vault change"
        } else {
            let preview = journalEntry.affectedFiles.prefix(2).joined(separator: ", ")
            let suffix = journalEntry.affectedFiles.count > 2 ? " +" + String(journalEntry.affectedFiles.count - 2) : ""
            description = "\(journalEntry.affectedFiles.count) file change: \(preview)\(suffix)"
        }
    }

    enum ActivityType {
        case ingest, query, lint, rollback
    }
}

private extension Date {
    static func fromISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum QuickAction {
    case ask, ingest, healthCheck
}
