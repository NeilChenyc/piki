import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(HomeViewModel.self) private var viewModel
    @Environment(WikiViewModel.self) private var wikiViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Main chat area
            VStack(spacing: 0) {
                // Chat messages
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(
                                message: message,
                                onToggleTrace: {
                                    viewModel.toggleTrace(messageId: message.id)
                                },
                                onWikiLinkTap: { target in
                                    Task { @MainActor in
                                        await wikiViewModel.loadIfNeeded(vaultURL: appState.vaultPath)
                                        guard wikiViewModel.selectPage(for: target) else { return }
                                        appState.selectedTab = .wiki
                                    }
                                }
                            )
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Quick actions
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

                // Input area
                ChatInputView(
                    placeholder: inputPlaceholder,
                    isDisabled: isInputDisabled,
                    showsStopButton: viewModel.isSending,
                    isStopping: viewModel.isStopping,
                    onSend: { text, files in
                        viewModel.sendMessage(text, appState: appState, selectedFiles: files)
                    },
                    onStop: {
                        viewModel.stopCurrentTask(appState: appState)
                    }
                )
                    .padding(16)
            }

            // Right panel
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
        .task(id: appState.vaultPath) {
            await viewModel.loadRecentJournal(appState: appState)
        }
    }

    private var isInputDisabled: Bool {
        false
    }

    private var inputPlaceholder: String {
        if !appState.isConnected { return "Connect to the runtime host before chatting" }
        if appState.vaultPath == nil { return "Select a vault before chatting" }
        if viewModel.isStopping { return "Stopping current run..." }
        if viewModel.isSending { return "Piki is working..." }
        if viewModel.pendingInputTaskId != nil { return "Reply to continue the current Claude task..." }
        return "Ask anything about your knowledge base..."
    }

    private var inputHint: String? {
        if !appState.isConnected {
            return appState.serviceErrorMessage ?? "Runtime host is disconnected."
        }
        if let prompt = viewModel.pendingInputPrompt, !prompt.isEmpty {
            return prompt
        }
        if appState.vaultPath == nil {
            return "Choose a vault in Settings before sending a message."
        }
        if appState.serviceHealth?.agentRuntimeConfigured != true {
            return appState.runtimeModeDetail
        }
        return nil
    }
}
