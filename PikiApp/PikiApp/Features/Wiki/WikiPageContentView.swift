import SwiftUI

struct WikiPageContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(WikiViewModel.self) private var wikiViewModel

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

            VStack(alignment: .leading, spacing: 20) {
                if page.content.isEmpty {
                    Text("No content yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(24)
                } else {
                    DocumentMarkdownView(
                        page.content,
                        presentationMode: .documentPage(displayTitle: page.title),
                        baseURL: URL(fileURLWithPath: page.filePath).deletingLastPathComponent(),
                        onOpenWikiLink: openWikiLink
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                if !page.relatedConcepts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Related Concepts")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        FlowLayout(spacing: 6) {
                            ForEach(page.relatedConcepts, id: \.self) { target in
                                WikiLinkCapsule(
                                    target: target,
                                    isEnabled: wikiViewModel.page(for: target) != nil,
                                    action: {
                                        openWikiLink(target)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openWikiLink(_ target: WikiLinkTarget) {
        guard wikiViewModel.selectPage(for: target) else { return }
        appState.selectedTab = .wiki
    }
}
