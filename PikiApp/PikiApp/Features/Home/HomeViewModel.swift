import SwiftUI
import OSLog

enum HomeTemplateAction {
    case inboxIngest(fileURL: URL, fileName: String)
    case runLintAndFix
}

@Observable
@MainActor
final class HomeViewModel {
    static let healthCheckPrompt =
        "请对当前 vault 运行 health check，并总结运行时连通性、配置状态、潜在风险和建议的下一步。"
    static let podcastPrompt =
        """
        我想上传一集播客并自动转录。请按播客转录流程先完成完整转录，再整理进知识库。

        播客链接：
        请把这里替换为单集链接后再发送。
        """

    private let logger = Logger(subsystem: "com.piki.app", category: "HomeViewModel")

    var messages: [ChatMessage] = []
    var recentActivity: [ActivityEntry] = []
    var inputText: String = ""
    var chatInputExternalRequest: ChatInputExternalRequest?
    var isSending = false
    var isStopping = false
    var statusText: String?
    var pendingInputTaskId: String?
    var pendingInputPrompt: String?
    var debugEventCount: Int = 0
    var debugLastEventType: String?
    var debugRecentEvents: [String] = []
    private var conversationId = UUID().uuidString
    private var activeTaskId: String?
    private var activeAssistantMessageId: String?
    private var currentRunTask: Task<Void, Never>?

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    func sendMessage(_ text: String, appState: AppState, selectedFiles: [URL] = []) {
        guard !isSending else { return }
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
                timestamp: Date(),
                traceItems: [
                    ChatTraceItem(
                        key: "run",
                        kind: "agent_run",
                        title: "正在思考",
                        summary: "正在创建任务并准备本轮任务。",
                        category: "model",
                        status: "running"
                    )
                ],
                isRunning: true,
                isTraceExpanded: false,
                isAgentRun: true,
                runStatus: "running"
            )
        )
        isSending = true
        isStopping = false
        statusText = "Creating task..."
        activeAssistantMessageId = assistantMessageId
        currentRunTask = Task {
            await runTask(
                text,
                selectedFiles: selectedFiles,
                vaultPath: vaultPath,
                appState: appState,
                assistantMessageId: assistantMessageId
            )
        }
    }

    func stopCurrentTask(appState: AppState) {
        guard !isStopping else { return }
        guard currentRunTask != nil || activeAssistantMessageId != nil else { return }
        isStopping = true
        statusText = "正在停止当前任务"

        guard let taskId = activeTaskId else {
            logger.log("Stopping local-only run before task id is available.")
            finalizeStoppedRun(summary: "本轮任务已停止。")
            return
        }

        Task {
            do {
                let task = try await appState.runtimeService.cancelTask(taskId: taskId)
                logger.log("Task cancellation acknowledged by backend for \(taskId, privacy: .public).")
                finalizeStoppedRun(summary: task.summary ?? "本轮任务已停止。")
            } catch {
                logger.error("Task cancellation failed for \(taskId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if shouldFallbackToLocalStop(after: error) {
                    finalizeStoppedRun(summary: "本轮任务已停止。")
                    return
                }
                isStopping = false
                statusText = "停止失败：\(error.localizedDescription)"
                appendSystemMessage("停止当前任务失败：\(error.localizedDescription)")
            }
        }
    }

    func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .ask:
            break
        case .uploadFile:
            chatInputExternalRequest = .openLocalFilePicker
        case .healthCheck:
            inputText = Self.healthCheckPrompt
        }
    }

    func preparePodcastPrompt() {
        inputText = Self.podcastPrompt
    }

    func consumeChatInputExternalRequest() {
        chatInputExternalRequest = nil
    }

    func submitTemplateAction(_ action: HomeTemplateAction, appState: AppState) {
        appState.selectedTab = .home

        guard !isSending else {
            appendSystemMessage("当前已有进行中的任务，完成后再试。")
            return
        }

        switch action {
        case .inboxIngest(let fileURL, _):
            sendMessage(
                "请帮我 ingest 这个文件，并整理进知识库。请在需要时创建或更新合适的 wiki 页面、补充必要链接，并在完成后告诉我结果。",
                appState: appState,
                selectedFiles: [fileURL]
            )

        case .runLintAndFix:
            sendMessage(
                "请对当前 vault 运行 lint，尽量直接修复低风险问题，并汇报主要问题、修复内容和剩余风险。",
                appState: appState
            )
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
            let effectiveText = text.isEmpty ? "请摄入这个文件。" : text
            let bufferedSelectedPaths = try await uploadSelectedFiles(selectedFiles, appState: appState)
            let response: TaskCreateResponse
            if let pendingTaskId = pendingInputTaskId {
                response = TaskCreateResponse(taskId: pendingTaskId, status: "running")
                _ = try await appState.runtimeService.submitTaskInput(taskId: pendingTaskId, message: effectiveText)
                pendingInputTaskId = nil
                pendingInputPrompt = nil
            } else {
                let request = TaskCreateRequest(
                    vaultPath: vaultPath.path(percentEncoded: false),
                    userInput: effectiveText,
                    selectedPaths: bufferedSelectedPaths,
                    actionContext: taskActionContext(for: effectiveText, selectedFiles: selectedFiles),
                    conversationId: conversationId,
                    asyncMode: true
                )
                response = try await appState.runtimeService.createTask(request)
            }
            activeTaskId = response.taskId
            statusText = "正在理解请求"

            var finalEventContent: String?
            for try await event in appState.runtimeService.taskEvents(taskId: response.taskId) {
                try Task.checkCancellation()
                recordDebugEvent(event)
                if let content = handle(event, assistantMessageId: assistantMessageId) {
                    finalEventContent = content
                }
            }

            try Task.checkCancellation()
            let task = try await appState.runtimeService.getTask(taskId: response.taskId)
            if let lintResult = task.output?.lintResult {
                appState.cacheLintResult(lintResult)
            }
            let content = preferredFinalContent(
                id: assistantMessageId,
                fallback: task.output?.answer
                    ?? task.output?.summary
                    ?? task.summary
                    ?? finalEventContent
                    ?? "Task finished without a final message."
            )
            if task.status == "cancelled" {
                stopMessage(id: assistantMessageId, content: content)
            } else if task.status == "input_required" {
                setAwaitingInput(id: assistantMessageId, content: content)
            } else {
                finishMessage(id: assistantMessageId, content: content)
            }
            await loadRecentJournal(appState: appState)
            statusText = nil
        } catch is CancellationError {
            statusText = nil
        } catch {
            failMessage(id: assistantMessageId, content: "任务执行失败：\(error.localizedDescription)")
            statusText = nil
        }
        if activeTaskId == nil || activeTaskId == pendingInputTaskId {
            activeAssistantMessageId = nil
        }
        activeTaskId = nil
        currentRunTask = nil
        isSending = false
        isStopping = false
    }

    func loadRecentJournal(appState: AppState) async {
        guard appState.isConnected, let vaultPath = appState.vaultPath else { return }
        do {
            let entries = try await appState.runtimeService.recentJournal(
                limit: 10,
                vaultPath: vaultPath.path(percentEncoded: false)
            )
            guard !Task.isCancelled else { return }
            recentActivity = entries.map(ActivityEntry.init(journalEntry:))
        } catch {
            guard !Task.isCancelled else { return }
            statusText = "Unable to load write activity: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func handle(_ event: TaskEvent, assistantMessageId: String) -> String? {
        switch event.renderEvent {
        case let .progress(stage, title, detail, category):
            reclaimLiveAnswerToTraceIfNeeded(
                id: assistantMessageId,
                for: event,
                nextTitle: title
            )
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: "stage:\(stage)",
                kind: "progress",
                title: title,
                summary: detail,
                category: category,
                status: "running"
            )
            if !detail.isEmpty {
                statusText = "\(title) · \(detail)"
            } else {
                statusText = title
            }
            return nil
        case let .answerDelta(delta):
            if !delta.isEmpty {
                upsertTraceEvent(
                    messageId: assistantMessageId,
                    key: "answering",
                    kind: "answering",
                    title: "正在生成回答",
                    summary: "正在流式生成本轮回复。",
                    category: "model",
                    status: "running"
                )
                appendLiveDelta(id: assistantMessageId, delta: delta)
                statusText = "正在生成回答"
            }
            return nil
        case let .traceDelta(delta):
            reclaimLiveAnswerToTraceIfNeeded(id: assistantMessageId, for: event, nextTitle: "正在继续思考")
            if !delta.isEmpty {
                appendTraceDelta(
                    id: assistantMessageId,
                    key: "reasoning",
                    title: "思考过程",
                    delta: delta
                )
            }
            return nil
        case let .trace(kind, title, summary, category, status):
            reclaimLiveAnswerToTraceIfNeeded(
                id: assistantMessageId,
                for: event,
                nextTitle: title
            )
            appendTraceEvent(
                messageId: assistantMessageId,
                kind: kind,
                title: title,
                summary: summary,
                category: category,
                status: status
            )
            return nil
        case let .toolStarted(key, title, summary, category):
            reclaimLiveAnswerToTraceIfNeeded(
                id: assistantMessageId,
                for: event,
                nextTitle: title
            )
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: key,
                kind: "tool_started",
                title: title,
                summary: summary,
                category: category,
                status: "running"
            )
            return nil
        case let .toolFinished(key, title, summary, category, status):
            reclaimLiveAnswerToTraceIfNeeded(
                id: assistantMessageId,
                for: event,
                nextTitle: title
            )
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: key,
                kind: status == "failed" ? "tool_failed" : "tool_finished",
                title: title,
                summary: summary,
                category: category,
                status: status
            )
            return nil
        case let .completed(content):
            let content = preferredFinalContent(
                id: assistantMessageId,
                fallback: content ?? "Task completed."
            )
            pendingInputTaskId = nil
            pendingInputPrompt = nil
            statusText = "已完成"
            markRunFinished(id: assistantMessageId, status: "completed")
            finishMessage(id: assistantMessageId, content: content)
            return content
        case let .cancelled(content):
            pendingInputTaskId = nil
            pendingInputPrompt = nil
            statusText = "已停止"
            markRunFinished(id: assistantMessageId, status: "cancelled")
            stopMessage(
                id: assistantMessageId,
                content: preferredFinalContent(
                    id: assistantMessageId,
                    fallback: content ?? "本轮任务已停止。"
                )
            )
            return content
        case let .failed(failure):
            pendingInputTaskId = nil
            pendingInputPrompt = nil
            markRunFinished(id: assistantMessageId, status: "failed")
            failMessage(
                id: assistantMessageId,
                content: failure.displayText,
                errorAction: failure.action
            )
            statusText = nil
            return failure.message
        case let .runCompleted(preview):
            statusText = "正在整理回答"
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: "run",
                kind: "agent_run",
                title: "任务已完成",
                summary: preview ?? "正在整理最终回答。",
                category: "model",
                status: "completed"
            )
            return nil
        case .runStarted:
            statusText = "正在思考"
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: "run",
                kind: "agent_run",
                title: "正在思考",
                summary: "Agent 已启动，正在规划本轮步骤。",
                category: "model",
                status: "running"
            )
            return nil
        case let .inputRequired(taskId, prompt):
            pendingInputTaskId = taskId ?? pendingInputTaskId
            pendingInputPrompt = prompt
            statusText = pendingInputPrompt ?? "需要你的输入"
            setRunStatus(id: assistantMessageId, status: "input_required")
            if let prompt = pendingInputPrompt, !prompt.isEmpty {
                upsertTraceEvent(
                    messageId: assistantMessageId,
                    key: "input_requested",
                    kind: "input_requested",
                    title: "等待你的输入",
                    summary: prompt,
                    category: "input",
                    status: "running"
                )
                updateMessage(id: assistantMessageId, content: prompt)
            }
            return pendingInputPrompt
        case .inputResolved:
            statusText = "已收到你的输入"
            upsertTraceEvent(
                messageId: assistantMessageId,
                key: "input_requested",
                kind: "input_requested",
                title: "已收到你的输入",
                summary: "Agent 将继续刚才中断的流程。",
                category: "input",
                status: "completed"
            )
            return nil
        case let .ignored(status):
            if let status {
                statusText = status
            }
            return nil
        }
    }

    @discardableResult
    func handleForTesting(_ event: TaskEvent, assistantMessageId: String) -> String? {
        handle(event, assistantMessageId: assistantMessageId)
    }

    private func updateMessage(id: String, content: String) {
        mutateMessage(id: id) { message in
            message.content = content
        }
    }

    private func preferredFinalContent(id: String, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }
        if let message = messages.first(where: { $0.id == id }) {
            let live = message.liveContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty {
                return live
            }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty, message.runStatus == "completed" {
                return content
            }
        }
        return fallback
    }

    private func appendLiveDelta(id: String, delta: String) {
        mutateMessage(id: id) { message in
            if !message.hasStartedAnswering {
                message.hasStartedAnswering = true
            }
            message.liveContent += delta
        }
    }

    private func reclaimLiveAnswerToTraceIfNeeded(id: String, for event: TaskEvent, nextTitle: String) {
        mutateMessage(id: id) { message in
            guard message.isRunning, message.hasStartedAnswering else { return }
            guard shouldReclaimLiveAnswer(for: event) else { return }

            let trimmedLive = message.liveContent.trimmingCharacters(in: .whitespacesAndNewlines)
            message.hasStartedAnswering = false

            guard !trimmedLive.isEmpty else { return }

            if let index = message.traceItems.firstIndex(where: { $0.key == "reasoning" }) {
                if !message.traceItems[index].summary.isEmpty {
                    message.traceItems[index].summary += "\n\n"
                }
                message.traceItems[index].summary += trimmedLive
                message.traceItems[index].title = nextTitle
                message.traceItems[index].status = "running"
            } else {
                message.traceItems.append(
                    ChatTraceItem(
                        key: "reasoning",
                        kind: "model_delta",
                        title: nextTitle,
                        summary: trimmedLive,
                        category: "model",
                        status: "running"
                    )
                )
            }

            message.liveContent = ""
        }
    }

    private func shouldReclaimLiveAnswer(for event: TaskEvent) -> Bool {
        switch event.type {
        case "tool.started", "tool.finished", "tool.failed", "agent.trace.delta", "agent.trace.event":
            return true
        case "agent.progress":
            let title = event.payload.title ?? ""
            return title != "正在生成回答" && title != "已完成"
        default:
            return false
        }
    }

    private func uploadSelectedFiles(_ selectedFiles: [URL], appState: AppState) async throws -> [String] {
        guard !selectedFiles.isEmpty else { return [] }
        statusText = "正在上传附件"
        var bufferedPaths: [String] = []
        for fileURL in selectedFiles {
            let uploaded = try await appState.runtimeService.uploadFile(fileURL)
            bufferedPaths.append(uploaded.bufferedPath)
        }
        return bufferedPaths
    }

    private func taskActionContext(for text: String, selectedFiles: [URL]) -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedFiles.isEmpty {
            return ["action": "ingest_file"]
        }
        if let url = detectPodcastEpisodeURL(in: trimmed) {
            return [
                "action": "podcast_transcribe",
                "podcast_url": url,
            ]
        }
        if trimmed.contains("播客转录") {
            return ["action": "podcast_transcribe"]
        }
        return [:]
    }

    private func detectPodcastEpisodeURL(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let pattern = #"https://www\.xiaoyuzhoufm\.com/episode/[A-Za-z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private func appendTraceDelta(id: String, key: String, title: String, delta: String) {
        mutateMessage(id: id) { message in
            if let index = message.traceItems.firstIndex(where: { $0.key == key }) {
                message.traceItems[index].summary += delta
                message.traceItems[index].status = "running"
                return
            }
            message.traceItems.append(
                ChatTraceItem(
                    key: key,
                    kind: "model_delta",
                    title: title,
                    summary: delta,
                    category: "model",
                    status: "running"
                )
            )
        }
    }


    private func appendTraceEvent(
        messageId: String,
        kind: String,
        title: String,
        summary: String,
        category: String?,
        status: String?
    ) {
        mutateMessage(id: messageId) { message in
            if message.traceItems.last?.kind == kind,
               message.traceItems.last?.title == title,
               message.traceItems.last?.summary == summary {
                return
            }
            message.traceItems.append(
                ChatTraceItem(
                    key: UUID().uuidString,
                    kind: kind,
                    title: title,
                    summary: summary,
                    category: category ?? "",
                    status: status ?? ""
                )
            )
        }
    }

    private func upsertTraceEvent(
        messageId: String,
        key: String,
        kind: String,
        title: String,
        summary: String,
        category: String,
        status: String
    ) {
        mutateMessage(id: messageId) { message in
            if let index = message.traceItems.firstIndex(where: { $0.key == key }) {
                message.traceItems[index].kind = kind
                message.traceItems[index].title = title
                if !summary.isEmpty {
                    message.traceItems[index].summary = summary
                }
                message.traceItems[index].category = category
                message.traceItems[index].status = status
                return
            }
            message.traceItems.append(
                ChatTraceItem(
                    key: key,
                    kind: kind,
                    title: title,
                    summary: summary,
                    category: category,
                    status: status
                )
            )
        }
    }

    private func finishMessage(id: String, content: String) {
        mutateMessage(id: id) { message in
            message.content = content
            message.liveContent = ""
            message.isRunning = false
            message.isTraceExpanded = false
            message.runStatus = message.runStatus == "running" ? "completed" : message.runStatus
        }
    }

    private func failMessage(id: String, content: String, errorAction: UserFacingErrorAction? = nil) {
        mutateMessage(id: id) { message in
            message.content = content
            message.liveContent = ""
            message.isRunning = false
            message.isTraceExpanded = false
            message.runStatus = "failed"
            message.errorAction = errorAction
        }
    }

    private func stopMessage(id: String, content: String) {
        mutateMessage(id: id) { message in
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                message.content = trimmed
            } else if !message.liveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.content = message.liveContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.content = "本轮任务已停止。"
            }
            message.liveContent = ""
            message.isRunning = false
            message.isTraceExpanded = false
            message.runStatus = "cancelled"
        }
    }

    private func setAwaitingInput(id: String, content: String) {
        mutateMessage(id: id) { message in
            message.content = content
            message.liveContent = ""
            message.isRunning = false
            message.isTraceExpanded = false
            message.runStatus = "input_required"
        }
    }

    private func markRunFinished(id: String, status: String) {
        mutateMessage(id: id) { message in
            message.runStatus = status
            for index in message.traceItems.indices {
                if message.traceItems[index].status == "running" {
                    message.traceItems[index].status = switch status {
                    case "failed": "failed"
                    case "cancelled": "cancelled"
                    default: "completed"
                    }
                }
            }
        }
    }

    private func setRunStatus(id: String, status: String) {
        mutateMessage(id: id) { message in
            message.runStatus = status
        }
    }

    func toggleTrace(messageId: String) {
        mutateMessage(id: messageId) { message in
            message.isTraceExpanded.toggle()
        }
    }

    func handleErrorAction(_ action: UserFacingErrorAction, appState: AppState) {
        if action.target == "settings.tingwu" {
            appState.selectedTab = .settings
            statusText = "请在设置中检查播客转录配置"
        }
    }

    private func mutateMessage(id: String, _ mutate: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var updatedMessages = messages
        var message = updatedMessages[index]
        mutate(&message)
        updatedMessages[index] = message
        messages = updatedMessages
    }

    private func recordDebugEvent(_ event: TaskEvent) {
        let detail = event.payload.title
            ?? event.payload.summary
            ?? event.payload.delta
            ?? event.payload.detail
            ?? ""
        let line = detail.isEmpty ? event.type : "\(event.type) · \(detail)"
        debugEventCount += 1
        debugLastEventType = event.type
        debugRecentEvents.insert(line, at: 0)
        if debugRecentEvents.count > 8 {
            debugRecentEvents.removeLast(debugRecentEvents.count - 8)
        }
        logger.log("Piki task event: \(line, privacy: .public)")
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

    private func stoppedContent(for id: String, summary: String?) -> String {
        let preferred = preferredFinalContent(id: id, fallback: summary ?? "")
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本轮任务已停止。" : trimmed
    }

    private func finalizeStoppedRun(summary: String) {
        currentRunTask?.cancel()
        currentRunTask = nil
        pendingInputTaskId = nil
        pendingInputPrompt = nil
        activeTaskId = nil
        isSending = false
        isStopping = false
        if let assistantMessageId = activeAssistantMessageId {
            stopMessage(
                id: assistantMessageId,
                content: stoppedContent(for: assistantMessageId, summary: summary)
            )
        }
        activeAssistantMessageId = nil
        statusText = "已停止当前任务"
    }

    private func shouldFallbackToLocalStop(after error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .connectionFailed, .invalidResponse, .serverError:
                return true
            case .userFacing(let error):
                return error.code == "task.not_found" || error.retryable
            case .serverMessage(let message):
                let normalized = message.lowercased()
                return normalized.contains("not found")
                    || normalized.contains("404")
                    || normalized.contains("task not found")
                    || normalized.contains("cannot be cancelled")
            }
        }
        return true
    }
}

struct ChatMessage: Identifiable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var citations: [Citation] = []
    var liveContent: String = ""
    var traceItems: [ChatTraceItem] = []
    var isRunning: Bool = false
    var isTraceExpanded: Bool = false
    var hasStartedAnswering: Bool = false
    var isAgentRun: Bool = false
    var runStatus: String = ""
    var errorAction: UserFacingErrorAction?

    enum MessageRole {
        case user, assistant, system
    }
}

struct ChatTraceItem: Identifiable {
    let id = UUID().uuidString
    let key: String
    var kind: String
    var title: String
    var summary: String
    var category: String
    var status: String
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

    init(
        id: String,
        description: String,
        timestamp: Date,
        type: ActivityType,
        journalId: String? = nil,
        affectedFiles: [String] = [],
        status: String = ""
    ) {
        self.id = id
        self.description = description
        self.timestamp = timestamp
        self.type = type
        self.journalId = journalId
        self.affectedFiles = affectedFiles
        self.status = status
    }

    init(journalEntry: JournalEntry) {
        id = journalEntry.id
        journalId = journalEntry.id
        affectedFiles = journalEntry.affectedFiles
        status = journalEntry.status
        timestamp = Date.fromISO8601(journalEntry.createdAt) ?? Date()
        type = .ingest
        let visibleFiles = journalEntry.affectedFiles.filter { !$0.hasPrefix("system/") }
        if journalEntry.affectedFiles.isEmpty {
            description = "写入记录"
        } else if visibleFiles.isEmpty {
            description = "内部状态更新"
        } else {
            let preview = visibleFiles.prefix(2).joined(separator: ", ")
            let suffix = visibleFiles.count > 2 ? " +" + String(visibleFiles.count - 2) : ""
            let hiddenSystemCount = journalEntry.affectedFiles.count - visibleFiles.count
            if hiddenSystemCount > 0 {
                description = "\(visibleFiles.count) 个知识文件变更：\(preview)\(suffix)（另含 \(hiddenSystemCount) 个内部状态文件）"
            } else {
                description = "\(visibleFiles.count) 个知识文件变更：\(preview)\(suffix)"
            }
        }
    }

    enum ActivityType {
        case ingest, query, lint
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

enum QuickAction: CaseIterable {
    case uploadFile, ask, healthCheck

    var title: String {
        switch self {
        case .uploadFile: return "上传文件"
        case .ask: return "提个问题"
        case .healthCheck: return "运行健康检查"
        }
    }

    var icon: String {
        switch self {
        case .uploadFile: return "doc.badge.plus"
        case .ask: return "questionmark.circle"
        case .healthCheck: return "heart.text.square"
        }
    }
}
