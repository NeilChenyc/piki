import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let onToggleTrace: () -> Void
    let onWikiLinkTap: (WikiLinkTarget) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    if message.role == .assistant && message.isAgentRun {
                        agentRunHeader
                    }

                    if shouldShowTrace {
                        traceView
                    }

                    if !displayContent.isEmpty {
                        if message.role == .assistant {
                            MessageMarkdownView(displayContent, onOpenWikiLink: onWikiLinkTap)
                        } else {
                            Text(displayContent)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                    } else if message.role == .assistant && message.isAgentRun {
                        Text(message.isRunning ? "Agent 正在执行本轮任务…" : "本轮 Agent Run 暂无最终正文。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Theme.accentLight : Theme.cardBackground)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

                if message.role == .assistant, !message.traceItems.isEmpty {
                    Button(action: onToggleTrace) {
                        HStack(spacing: 4) {
                            Image(systemName: message.isTraceExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(message.isTraceExpanded ? "收起过程" : "展开过程")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .padding(.top, 2)
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

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var shouldShowTrace: Bool {
        message.role == .assistant
            && !message.traceItems.isEmpty
            && ((message.isRunning && !message.hasStartedAnswering) || message.isTraceExpanded)
    }

    private var agentRunHeader: some View {
        HStack(spacing: 8) {
            Label("Agent Run", systemImage: "sparkles.rectangle.stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(runStatusTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(runStatusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(runStatusColor.opacity(0.12))
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .padding(.bottom, shouldShowTrace ? 2 : 0)
    }

    private var displayContent: String {
        if message.isRunning {
            return message.liveContent.isEmpty ? message.content : message.liveContent
        }
        return message.content
    }

    private var traceView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.traceItems) { item in
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
                .fill(Theme.surfaceSecondary)
        )
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
}
