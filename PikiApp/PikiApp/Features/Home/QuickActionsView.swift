import SwiftUI

struct QuickActionsView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            QuickActionChip(
                title: "Ask a question",
                icon: "questionmark.circle",
                action: { onAction(.ask) }
            )
            QuickActionChip(
                title: "Ingest a source",
                icon: "doc.badge.plus",
                action: { onAction(.ingest) }
            )
            QuickActionChip(
                title: "Run health check",
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
            .foregroundStyle(Theme.primary)
            .background(Theme.primaryLight)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
