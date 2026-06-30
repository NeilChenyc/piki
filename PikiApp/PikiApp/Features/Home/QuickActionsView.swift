import SwiftUI

struct QuickActionsView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(QuickAction.allCases, id: \.self) { item in
                QuickActionChip(
                    title: item.title,
                    icon: item.icon,
                    action: { onAction(item) }
                )
            }
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
