import SwiftUI

struct WikiPageContentView: View {
    let page: WikiPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Breadcrumb
            HStack(spacing: 4) {
                Text("Wiki")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textTertiary)
                Text(page.category.capitalized)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textTertiary)
                Text(page.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Edit", systemImage: "pencil") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("History", systemImage: "clock") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Page title
                    Text(page.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    // Content placeholder
                    if page.content.isEmpty {
                        Text("No content yet")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text(page.content)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(4)
                    }

                    // Related concepts
                    if !page.relatedConcepts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Related Concepts")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            FlowLayout(spacing: 6) {
                                ForEach(page.relatedConcepts, id: \.self) { concept in
                                    Text(concept)
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .foregroundStyle(Theme.primary)
                                        .background(Theme.primaryLight)
                                        .clipShape(.capsule)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}
