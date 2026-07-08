import SwiftUI

struct ChatBubbleDisplayState {
    let message: ChatMessage

    var headerTitle: String {
        message.isAgentRun ? "piki" : ""
    }

    var headerStatusText: String? {
        guard message.isAgentRun else { return nil }
        return currentTraceItem?.title
    }

    var shouldAnimateHeaderStatusText: Bool {
        guard message.isAgentRun, message.isRunning else { return false }
        guard let currentTraceItem else { return false }
        return currentTraceItem.status == "running" && !currentTraceItem.title.isEmpty
    }

    var shouldShowTraceSummaryRow: Bool {
        message.role == .assistant && currentTraceItem != nil && headerStatusText == nil
    }

    var shouldShowExpandedTraceHistory: Bool {
        message.role == .assistant && message.isTraceExpanded && !message.traceItems.isEmpty
    }

    var currentTraceItem: ChatTraceItem? {
        guard message.role == .assistant, !message.traceItems.isEmpty else { return nil }
        if let runningItem = message.traceItems.last(where: { $0.status == "running" }) {
            return runningItem
        }
        return message.traceItems.last
    }

    var runningReasoningPreview: String? {
        guard message.isAgentRun, message.isRunning, message.content.isEmpty, message.liveContent.isEmpty else {
            return nil
        }
        if let reasoning = message.traceItems.last(where: { $0.key == "reasoning" && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return reasoning.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let modelTrace = message.traceItems.last(where: {
            $0.category == "model"
            && $0.status == "running"
            && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return modelTrace.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    var runningFallbackText: String? {
        guard message.isAgentRun, message.content.isEmpty, message.liveContent.isEmpty else {
            return nil
        }
        if runningReasoningPreview != nil {
            return nil
        }
        if message.isRunning {
            return "正在执行本轮任务…"
        }
        return "本轮任务暂未生成最终正文。"
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onToggleTrace: () -> Void
    let onWikiLinkTap: (WikiLinkTarget) -> Void
    let onErrorAction: (UserFacingErrorAction) -> Void

    @State private var isHoveringTrace = false

    init(
        message: ChatMessage,
        onToggleTrace: @escaping () -> Void,
        onWikiLinkTap: @escaping (WikiLinkTarget) -> Void,
        onErrorAction: @escaping (UserFacingErrorAction) -> Void = { _ in }
    ) {
        self.message = message
        self.onToggleTrace = onToggleTrace
        self.onWikiLinkTap = onWikiLinkTap
        self.onErrorAction = onErrorAction
    }

    private var displayState: ChatBubbleDisplayState {
        ChatBubbleDisplayState(message: message)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant {
                    assistantContent
                } else {
                    userBubble
                }

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, message.role == .user ? 4 : 0)
            }
            .frame(maxWidth: message.role == .assistant ? .infinity : 620, alignment: message.role == .assistant ? .leading : .trailing)

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var userBubble: some View {
        Text(displayContent)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.subtleFill)
            .clipShape(.rect(cornerRadius: 16))
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.isAgentRun {
                agentRunHeader
            }

            if displayState.shouldShowTraceSummaryRow, let item = displayState.currentTraceItem {
                AgentTraceSummaryRow(
                    item: item,
                    isExpanded: message.isTraceExpanded,
                    showsDisclosure: !message.traceItems.isEmpty,
                    isHovering: isHoveringTrace,
                    onToggle: onToggleTrace
                )
                .onHover { isHoveringTrace = $0 }
            }

            if displayState.shouldShowExpandedTraceHistory {
                AgentTraceHistoryView(items: message.traceItems)
            }

            if !displayContent.isEmpty {
                MessageMarkdownView(displayContent, onOpenWikiLink: onWikiLinkTap)
            } else if let reasoningPreview = displayState.runningReasoningPreview {
                MessageMarkdownView(reasoningPreview, onOpenWikiLink: onWikiLinkTap)
            } else if let fallbackText = displayState.runningFallbackText {
                Text(fallbackText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let errorAction = message.errorAction {
                Button {
                    onErrorAction(errorAction)
                } label: {
                    Label(errorAction.label, systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.error)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.error.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.citations) { citation in
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: 3)
                            Text(citation.pageTitle)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.blue.opacity(0.05))
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var agentRunHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)

            Text(displayState.headerTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let headerStatusText = displayState.headerStatusText {
                RunningStatusText(
                    text: headerStatusText,
                    isActive: displayState.shouldAnimateHeaderStatusText,
                    font: .system(size: 12),
                    color: Theme.textSecondary,
                    lineLimit: 1
                )
            } else {
                Text(runStatusTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(runStatusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(runStatusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    private var displayContent: String {
        if message.isRunning {
            return message.liveContent.isEmpty ? message.content : message.liveContent
        }
        return message.content
    }

    private var runStatusTitle: String {
        switch message.runStatus {
        case "failed": "失败"
        case "cancelled": "已停止"
        case "input_required": "等待输入"
        case "completed": "已完成"
        default: message.isRunning ? "运行中" : "已准备"
        }
    }

    private var runStatusColor: Color {
        switch message.runStatus {
        case "failed": Theme.error
        case "cancelled": Theme.warning
        case "input_required": Theme.warning
        case "completed": Theme.primary
        default: Theme.textSecondary
        }
    }
}

private struct AgentTraceSummaryRow: View {
    let item: ChatTraceItem
    let isExpanded: Bool
    let showsDisclosure: Bool
    let isHovering: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color(for: item).opacity(0.12))
                        .frame(width: 20, height: 20)
                    Image(systemName: iconName(for: item))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: item))
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if showsDisclosure {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovering ? Theme.textSecondary : Theme.textTertiary.opacity(0.35))
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct AgentTraceHistoryView: View {
    let items: [ChatTraceItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(color(for: item).opacity(0.14))
                            .frame(width: 18, height: 18)
                        Image(systemName: iconName(for: item))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(color(for: item))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if !item.summary.isEmpty {
                            Text(item.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(item.kind == "model_delta" ? 8 : 3)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.subtleFill)
        )
    }
}

private func iconName(for item: ChatTraceItem) -> String {
    switch item.status {
    case "failed": return "xmark.circle.fill"
    case "completed": return "checkmark.circle.fill"
    default:
        switch item.category {
        case "read": return "book.fill"
        case "write": return "square.and.pencil"
        case "command": return "terminal.fill"
        case "convert": return "doc.text.fill"
        case "input": return "ellipsis.bubble.fill"
        case "model": return "sparkles"
        default: return "circle.dotted"
        }
    }
}

private func color(for item: ChatTraceItem) -> Color {
    switch item.status {
    case "failed": return Theme.error
    case "cancelled": return Theme.warning
    case "completed": return Theme.primary
    default: return Theme.textSecondary
    }
}
