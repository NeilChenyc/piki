import SwiftUI

struct WikiView: View {
    @Environment(AppState.self) private var appState
    @Environment(WikiViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            // Page tree navigation
            VStack(alignment: .leading, spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        TextField("Search pages...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackground)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )
                }
                .padding(12)

                Divider()

                // All pages label
                Text("All pages")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Category tree
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.error)
                                .padding(12)
                        }

                        if viewModel.isLoading && viewModel.categories.allSatisfy({ $0.pages.isEmpty }) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading pages...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(12)
                        } else {
                            ForEach(viewModel.filteredCategories) { category in
                                WikiCategorySection(
                                    category: category,
                                    selectedPage: viewModel.selectedPage
                                ) { page in
                                    viewModel.stopEditingSelectedPagePreservingDraft()
                                    viewModel.selectedPage = page
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            // Content area
            if let page = viewModel.selectedPage {
                WikiPageContentView(page: page)
            } else {
                VStack {
                    Image(systemName: "book")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Select a page to view")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: appState.vaultPath) {
            await viewModel.loadIfNeeded(vaultURL: appState.vaultPath)
        }
    }
}
