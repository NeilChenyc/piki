import SwiftUI

struct WikiView: View {
    @Environment(AppState.self) private var appState
    @Environment(WikiViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        TextField("搜索页面...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.elevatedCardBackground)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )

                    Button {
                        Task {
                            await viewModel.refreshWiki(vaultURL: appState.vaultPath)
                        }
                    } label: {
                        Group {
                            if viewModel.isRefreshInFlight {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.elevatedCardBackground)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshInFlight)
                }
                .padding(16)
                .padding(.top, 0)

                Divider()

                Text("全部页面")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

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
                                Text("正在加载页面...")
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
            .frame(
                minWidth: 200,
                idealWidth: DetailLayoutGuide.wikiSidebarIdealWidth,
                maxWidth: DetailLayoutGuide.wikiSidebarMaxWidth,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(Theme.secondaryPanelBackground)

            if let page = viewModel.selectedPage {
                WikiPageContentView(page: page)
                    .background(Theme.primaryPanelBackground)
            } else {
                VStack {
                    Image(systemName: "book")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textTertiary)
                    Text("选择一个页面以查看")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.primaryPanelBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryPanelBackground)
        .task(id: refreshTrigger) {
            guard isWikiVisible else { return }
            await viewModel.syncVisibleWiki(vaultURL: appState.vaultPath)
        }
    }

    private var isWikiVisible: Bool {
        appState.selectedTab == .wiki
    }

    private var refreshTrigger: String {
        let vaultPath = appState.vaultPath?.path(percentEncoded: false) ?? "no-vault"
        return "\(vaultPath)|\(appState.selectedTab.rawValue)|\(scenePhaseKey)"
    }

    private var scenePhaseKey: String {
        switch scenePhase {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }
}
