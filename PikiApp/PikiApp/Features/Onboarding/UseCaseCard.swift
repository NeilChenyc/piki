import SwiftUI

struct UseCaseCardMetrics {
    static let minWidth: CGFloat = 144
    static let maxWidth: CGFloat = 166
    static let minHeight: CGFloat = 92
    static let iconSize: CGFloat = 19
    static let titleSize: CGFloat = 13
    static let descriptionSize: CGFloat = 11
    static let contentPadding: CGFloat = 12
    static let contentSpacing: CGFloat = 7
    static let interCardSpacing: CGFloat = 10
}

struct UseCaseCard: View {
    let item: UseCaseItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: UseCaseCardMetrics.contentSpacing) {
                Image(systemName: item.icon)
                    .font(.system(size: UseCaseCardMetrics.iconSize))
                    .foregroundStyle(Theme.accent)

                Text(item.title)
                    .font(.system(size: UseCaseCardMetrics.titleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(item.description)
                    .font(.system(size: UseCaseCardMetrics.descriptionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(UseCaseCardMetrics.contentPadding)
            .frame(maxWidth: .infinity, minHeight: UseCaseCardMetrics.minHeight, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
}
