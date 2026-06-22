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

                if wikiViewModel.isEditingSelectedPage && wikiViewModel.selectedPage?.id == page.id {
                    Button("Cancel", role: .cancel) {
                        wikiViewModel.cancelEditingSelectedPage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Save", systemImage: "checkmark") {
                        do {
                            try wikiViewModel.saveEditingSelectedPage()
                        } catch {
                            wikiViewModel.errorMessage = "Failed to save page: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.primary)
                } else {
                    Button("A-", systemImage: "textformat.size.smaller") {
                        wikiViewModel.decreasePreviewTextScale()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!wikiViewModel.canDecreasePreviewTextScale)

                    Button("A+", systemImage: "textformat.size.larger") {
                        wikiViewModel.increasePreviewTextScale()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!wikiViewModel.canIncreasePreviewTextScale)

                    Button("Edit", systemImage: "pencil") {
                        wikiViewModel.startEditingSelectedPage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                if wikiViewModel.isEditingSelectedPage && wikiViewModel.selectedPage?.id == page.id {
                    if let editingText = wikiViewModel.editingText {
                        WikiMarkdownEditorView(
                            text: Binding(
                                get: { wikiViewModel.editingText ?? editingText },
                                set: { wikiViewModel.updateDraftForSelectedPage($0) }
                            )
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                    }
                } else {
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
                            textScale: wikiViewModel.previewTextScale,
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openWikiLink(_ target: WikiLinkTarget) {
        guard wikiViewModel.selectPage(for: target) else { return }
        appState.selectedTab = .wiki
    }
}
