import SwiftUI

struct UseCaseCard: View {
    let item: UseCaseItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(width: 200, alignment: .topLeading)
            .frame(minHeight: 120, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
}
