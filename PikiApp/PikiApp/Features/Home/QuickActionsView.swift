import SwiftUI

struct QuickActionsView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            QuickActionChip(
                title: "提个问题",
                icon: "questionmark.circle",
                action: { onAction(.ask) }
            )
            QuickActionChip(
                title: "添加素材",
                icon: "doc.badge.plus",
                action: { onAction(.ingest) }
            )
            QuickActionChip(
                title: "运行健康检查",
                icon: "heart.text.square",
                action: { onAction(.healthCheck) }
            )
            Spacer()
        }
    }
}

struct QuickActionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.subtleFill)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
