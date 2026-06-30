import SwiftUI

struct InboxView: View {
    @Environment(AppState.self) private var appState
    @Environment(HomeViewModel.self) private var homeViewModel
    @Environment(InboxViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("资料箱")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("拖入文件以添加到知识库")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)

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

                InboxFilterBar(
                    selectedDirectoryFilter: $viewModel.selectedDirectoryFilter,
                    selectedFileTypeFilter: $viewModel.selectedFileTypeFilter,
                    directoryCounts: viewModel.directoryCounts,
                    fileTypeCounts: viewModel.fileTypeCounts
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("搜索文件名...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.elevatedCardBackground)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
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
                                Text("正在加载文件...")
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
                    Text("\(viewModel.filteredItems.count) 项")
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
            .background(Theme.primaryPanelBackground)
            .frame(minWidth: 400, idealWidth: 500)

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
                .background(Theme.secondaryPanelBackground)
                .frame(minWidth: 400, idealWidth: 500)
            }
        }
        .background(Theme.primaryPanelBackground)
        .task(id: appState.vaultPath) {
            await viewModel.loadIfNeeded(vaultURL: appState.vaultPath)
        }
    }
}
