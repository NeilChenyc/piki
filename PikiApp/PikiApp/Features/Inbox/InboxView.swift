import SwiftUI

struct InboxView: View {
    @Environment(AppState.self) private var appState
    @Environment(HomeViewModel.self) private var homeViewModel
    @Environment(InboxViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            // Main list area
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inbox")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Drop files to add to your knowledge base")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Drop zone
                FileDropZone(
                    onDrop: { urls in
                        viewModel.handleFileDrop(urls, appState: appState)
                    },
                    onBrowse: {
                        viewModel.chooseFiles(appState: appState)
                    }
                )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // Filter tabs
                InboxFilterBar(
                    selectedFilter: $viewModel.selectedFilter,
                    counts: viewModel.filterCounts
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                Divider()

                // File list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.error)
                                .padding(16)
                        }
                        if viewModel.isLoading && viewModel.items.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading files...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(24)
                        } else {
                            ForEach(viewModel.filteredItems) { item in
                                InboxFileRow(
                                    item: item,
                                    isSelected: viewModel.selectedItem?.id == item.id
                                ) {
                                    viewModel.selectedItem = item
                                }
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("\(viewModel.filteredItems.count) items")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if let status = viewModel.statusMessage {
                        Spacer()
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(16)
            }

            // Preview panel
            if let item = viewModel.selectedItem {
                FilePreviewPanel(
                    item: item,
                    onIngest: {
                        guard let fileURL = item.filePath else { return }
                        homeViewModel.submitTemplateAction(
                            .inboxIngest(fileURL: fileURL, fileName: item.fileName),
                            appState: appState
                        )
                    },
                    onClear: {
                        viewModel.clear(item, appState: appState)
                    }
                )
                    .frame(width: 320)
            }
        }
        .task(id: appState.vaultPath) {
            await viewModel.loadIfNeeded(vaultURL: appState.vaultPath)
        }
    }
}
