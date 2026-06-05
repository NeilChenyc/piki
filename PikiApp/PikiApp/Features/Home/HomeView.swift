import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Main chat area
            VStack(spacing: 0) {
                // Header greeting
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.greeting)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your personal knowledge workspace is ready")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(runtimeModeColor)
                            .frame(width: 7, height: 7)
                        Text(appState.runtimeModeTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider()

                // Chat messages
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(message: message)
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
                    onSend: { text, files in
                        viewModel.sendMessage(text, appState: appState, selectedFiles: files)
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
        viewModel.isSending
    }

    private var inputPlaceholder: String {
        if !appState.isConnected { return "Connect to Agent Service before chatting" }
        if appState.vaultPath == nil { return "Select a vault before chatting" }
        if viewModel.isSending { return "Piki is working..." }
        return "Ask anything about your knowledge base..."
    }

    private var inputHint: String? {
        if !appState.isConnected {
            return appState.serviceErrorMessage ?? "Agent Service is disconnected."
        }
        if appState.vaultPath == nil {
            return "Choose a vault in Settings before sending a message."
        }
        if appState.serviceHealth?.sdkRuntimeConfigured != true {
            return appState.runtimeModeDetail
        }
        return nil
    }

    private var runtimeModeColor: Color {
        guard appState.isConnected else { return Theme.error }
        return appState.serviceHealth?.sdkRuntimeConfigured == true ? Theme.primary : Theme.warning
    }
}
