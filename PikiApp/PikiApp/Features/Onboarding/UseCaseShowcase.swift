import SwiftUI

struct UseCaseShowcase: View {
    let items: [UseCaseItem]
    let onSelect: (UseCaseItem) -> Void
    let onDismiss: () -> Void

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: UseCaseCardMetrics.minWidth,
                    maximum: UseCaseCardMetrics.maxWidth
                ),
                spacing: UseCaseCardMetrics.interCardSpacing
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("试试看")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: UseCaseCardMetrics.interCardSpacing) {
                ForEach(items) { item in
                    UseCaseCard(item: item) {
                        onSelect(item)
                    }
                }
            }
        }
    }
}
