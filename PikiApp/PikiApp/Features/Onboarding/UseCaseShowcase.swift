import SwiftUI

struct UseCaseShowcase: View {
    let items: [UseCaseItem]
    let onSelect: (UseCaseItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 12) {
                ForEach(items) { item in
                    UseCaseCard(item: item) {
                        onSelect(item)
                    }
                }
            }
        }
    }
}
