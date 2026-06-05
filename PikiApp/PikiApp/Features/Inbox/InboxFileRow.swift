import SwiftUI

struct InboxFileRow: View {
    let item: InboxItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: item.fileType.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(item.fileType.color)
                    .frame(width: 32, height: 32)
                    .background(item.fileType.color.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.fileSize)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                StatusBadge(status: item.status)

                Text(item.addedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.primaryLight : .clear)
        }
        .buttonStyle(.plain)
    }
}

struct StatusBadge: View {
    let status: InboxStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.1))
            .clipShape(.capsule)
    }
}
