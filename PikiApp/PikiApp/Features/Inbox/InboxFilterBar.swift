import SwiftUI

struct InboxFilterBar: View {
    @Binding var selectedFilter: InboxFilter
    let counts: [InboxFilter: Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(InboxFilter.allCases, id: \.self) { filter in
                FilterPill(
                    title: filter.title,
                    count: counts[filter] ?? 0,
                    isSelected: selectedFilter == filter
                ) {
                    selectedFilter = filter
                }
            }
            Spacer()
        }
    }
}

struct FilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : Theme.textSecondary)
            .background(isSelected ? Theme.primary : Theme.cardBackground)
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
