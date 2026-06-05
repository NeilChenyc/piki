import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let onToggleTrace: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    if shouldShowTrace {
                        traceView
                    }

                    if !displayContent.isEmpty {
                        Text(displayContent)
                            .font(.system(size: 13))
                            .foregroundStyle(message.role == .user ? .white : Theme.textPrimary)
                            .textSelection(.enabled)
                    } else if message.role == .assistant && !shouldShowTrace {
                        Text("Working...")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Theme.primary : Theme.cardBackground)
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
        message.role == .assistant && !message.traceItems.isEmpty && (message.isRunning || message.isTraceExpanded)
    }

    private var displayContent: String {
        if message.isRunning {
            return message.liveContent.isEmpty ? message.content : message.liveContent
        }
        return message.content
    }

    private var traceView: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(message.traceItems) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: iconName(for: item))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: item))
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        if !item.summary.isEmpty {
                            Text(item.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(item.kind == "model_delta" ? 4 : 2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func iconName(for item: ChatTraceItem) -> String {
        switch item.status {
        case "failed": return "xmark.circle.fill"
        case "completed": return "checkmark.circle.fill"
        default:
            switch item.category {
            case "read": return "book.fill"
            case "write": return "square.and.pencil"
            case "convert": return "doc.text.fill"
            case "model": return "sparkles"
            default: return "circle.dotted"
            }
        }
    }

    private func color(for item: ChatTraceItem) -> Color {
        switch item.status {
        case "failed": return Theme.error
        case "completed": return Theme.primary
        default: return Theme.textSecondary
        }
    }
}
