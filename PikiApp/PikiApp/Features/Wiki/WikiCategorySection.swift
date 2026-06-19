import SwiftUI

struct WikiCategorySection: View {
    let category: WikiCategory
    let selectedPage: WikiPage?
    let onSelect: (WikiPage) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12)
                    Image(systemName: category.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text(category.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(category.pages.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(category.pages) { page in
                    Button {
                        onSelect(page)
                    } label: {
                        Text(page.title)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                selectedPage?.id == page.id
                                    ? Theme.textPrimary
                                    : Theme.textPrimary
                            )
                            .padding(.leading, 36)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedPage?.id == page.id
                                    ? Theme.selection
                                    : .clear
                            )
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
