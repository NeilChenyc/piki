import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    if message.role == .assistant, !message.progressSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(message.progressSteps) { step in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.primary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(step.title)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Theme.textSecondary)
                                        if !step.detail.isEmpty {
                                            Text(step.detail)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.textTertiary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundStyle(message.role == .user ? .white : Theme.textPrimary)
                            .textSelection(.enabled)
                    } else if message.role == .assistant {
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
}
