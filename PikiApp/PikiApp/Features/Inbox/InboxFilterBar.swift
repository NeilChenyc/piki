import SwiftUI

struct InboxFilterBar: View {
    @Binding var selectedDirectoryFilter: InboxDirectoryFilter
    @Binding var selectedFileTypeFilter: InboxFileTypeFilter
    let directoryCounts: [InboxDirectoryFilter: Int]
    let fileTypeCounts: [InboxFileTypeFilter: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(InboxDirectoryFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.title,
                        count: directoryCounts[filter] ?? 0,
                        isSelected: selectedDirectoryFilter == filter
                    ) {
                        selectedDirectoryFilter = filter
                    }
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(InboxFileTypeFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.title,
                        count: fileTypeCounts[filter] ?? 0,
                        isSelected: selectedFileTypeFilter == filter
                    ) {
                        selectedFileTypeFilter = filter
                    }
                }
                Spacer()
            }
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
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .background(isSelected ? Theme.selection : Theme.elevatedCardBackground)
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
