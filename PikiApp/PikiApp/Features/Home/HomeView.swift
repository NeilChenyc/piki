import SwiftUI

@MainActor
struct HomeViewDisplayState {
    let isEmptyState: Bool
    let inputPlaceholder: String
    let inputHint: String?
    let emptyStateHint: String?

    init(appState: AppState, viewModel: HomeViewModel) {
        self.isEmptyState = viewModel.messages.isEmpty

        if isEmptyState {
            if viewModel.pendingInputTaskId != nil {
                inputPlaceholder = "继续这轮对话"
            } else if viewModel.isSending {
                inputPlaceholder = "正在处理你的请求"
            } else if viewModel.isStopping {
                inputPlaceholder = "正在停止当前任务"
            } else {
                inputPlaceholder = "有问题尽管问"
            }
        } else if !appState.isConnected {
            inputPlaceholder = "Connect to the runtime host before chatting"
        } else if appState.vaultPath == nil {
            inputPlaceholder = "Select a vault before chatting"
        } else if viewModel.isStopping {
            inputPlaceholder = "Stopping current run..."
        } else if viewModel.isSending {
            inputPlaceholder = "Piki is working..."
        } else if viewModel.pendingInputTaskId != nil {
            inputPlaceholder = "Reply to continue the current Claude task..."
        } else {
            inputPlaceholder = "Ask anything about your knowledge base..."
        }

        if !appState.isConnected {
            let message = appState.serviceErrorMessage ?? "Runtime host is disconnected."
            inputHint = message
            emptyStateHint = message
        } else if let prompt = viewModel.pendingInputPrompt, !prompt.isEmpty {
            inputHint = prompt
            emptyStateHint = prompt
        } else if appState.vaultPath == nil {
            inputHint = "Choose a vault in Settings before sending a message."
            emptyStateHint = "请先在设置里选择一个 vault。"
        } else if appState.serviceHealth?.agentRuntimeConfigured != true {
            inputHint = appState.runtimeModeDetail
            emptyStateHint = appState.runtimeModeDetail
        } else {
            inputHint = nil
            emptyStateHint = nil
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(HomeViewModel.self) private var viewModel
    @Environment(WikiViewModel.self) private var wikiViewModel
    @Namespace private var inputTransition

    var body: some View {
        Group {
            if isEmptyState {
                emptyStateView
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
            } else {
                chatStateView
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: isEmptyState)
        .task(id: appState.vaultPath) {
            await viewModel.loadRecentJournal(appState: appState)
        }
    }

    private var chatStateView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(
                                message: message,
                                onToggleTrace: {
                                    viewModel.toggleTrace(messageId: message.id)
                                },
                                onWikiLinkTap: handleWikiLinkTap(_:)
                            )
                        }
                    }
                    .padding(24)
                }

                Divider()

                QuickActionsView(onAction: viewModel.handleQuickAction)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                if let inputHint {
                    Text(inputHint)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                if let statusText = viewModel.statusText {
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                }

                ChatInputView(
                    placeholder: inputPlaceholder,
                    isDisabled: isInputDisabled,
                    showsStopButton: viewModel.isSending,
                    isStopping: viewModel.isStopping,
                    style: .docked,
                    helperText: nil,
                    autofocus: true,
                    onSend: { text, files in
                        viewModel.sendMessage(text, appState: appState, selectedFiles: files)
                    },
                    onStop: {
                        viewModel.stopCurrentTask(appState: appState)
                    }
                )
                .matchedGeometryEffect(id: "home-input-shell", in: inputTransition)
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 16) {
                VaultStatusCard(status: appState.connectionStatus, vaultURL: appState.vaultPath)
                RecentActivityList(
                    entries: viewModel.recentActivity,
                    onRollback: { entry in
                        viewModel.rollback(entry, appState: appState)
                    }
                )
                Spacer()
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    private var emptyStateView: some View {
        VStack {
            Spacer(minLength: 48)

            VStack(spacing: 36) {
                PikiLogo()
                    .frame(width: 280, height: 124)

                VStack(alignment: .leading, spacing: 12) {
                    ChatInputView(
                        placeholder: inputPlaceholder,
                        isDisabled: isInputDisabled,
                        showsStopButton: viewModel.isSending,
                        isStopping: viewModel.isStopping,
                        style: .hero,
                        helperText: emptyStateHint,
                        autofocus: true,
                        onSend: { text, files in
                            viewModel.sendMessage(text, appState: appState, selectedFiles: files)
                        },
                        onStop: {
                            viewModel.stopCurrentTask(appState: appState)
                        }
                    )
                    .matchedGeometryEffect(id: "home-input-shell", in: inputTransition)
                }
                .frame(maxWidth: 1160)
                .padding(.horizontal, 40)
            }

            Spacer(minLength: 96)
        }
    }

    private var isInputDisabled: Bool {
        false
    }

    private var isEmptyState: Bool {
        displayState.isEmptyState
    }

    private var inputPlaceholder: String {
        displayState.inputPlaceholder
    }

    private var inputHint: String? {
        displayState.inputHint
    }

    private var emptyStateHint: String? {
        displayState.emptyStateHint
    }

    private var displayState: HomeViewDisplayState {
        HomeViewDisplayState(appState: appState, viewModel: viewModel)
    }

    private func handleWikiLinkTap(_ target: WikiLinkTarget) {
        Task { @MainActor in
            await wikiViewModel.loadIfNeeded(vaultURL: appState.vaultPath)
            guard wikiViewModel.selectPage(for: target) else { return }
            appState.selectedTab = .wiki
        }
    }
}
