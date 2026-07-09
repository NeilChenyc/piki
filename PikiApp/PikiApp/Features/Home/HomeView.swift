import SwiftUI
import TipKit

@MainActor
struct HomeViewDisplayState {
    let isEmptyState: Bool
    let inputPlaceholder: String
    let inputHint: String?
    let emptyStateHint: String?
    let shouldAnimateStatusText: Bool

    init(appState: AppState, viewModel: HomeViewModel) {
        self.isEmptyState = viewModel.messages.isEmpty
        self.shouldAnimateStatusText = viewModel.isSending && viewModel.statusText != nil

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
            inputPlaceholder = "连接运行时服务后方可对话"
        } else if appState.vaultPath == nil {
            inputPlaceholder = "选择知识库后方可对话"
        } else if viewModel.isStopping {
            inputPlaceholder = "正在停止当前任务..."
        } else if viewModel.isSending {
            inputPlaceholder = "Piki 正在处理..."
        } else if viewModel.pendingInputTaskId != nil {
            inputPlaceholder = "继续回复以推进当前 Claude 任务..."
        } else {
            inputPlaceholder = "上传新知识或随意提问"
        }

        if !appState.isConnected {
            let message = appState.serviceErrorMessage ?? "运行时服务已断线。"
            inputHint = message
            emptyStateHint = message
        } else if let prompt = viewModel.pendingInputPrompt, !prompt.isEmpty {
            inputHint = prompt
            emptyStateHint = prompt
        } else if appState.vaultPath == nil {
            inputHint = "请先在设置里选择一个知识库。"
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

struct HomeEmptyStateLayoutMetrics {
    static let maxContentWidth: CGFloat = 680
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 22

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, min(maxContentWidth, availableWidth - horizontalPadding * 2))
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(HomeViewModel.self) private var viewModel
    @Environment(WikiViewModel.self) private var wikiViewModel
    @Environment(OnboardingViewModel.self) private var onboardingVM
    @Namespace private var inputTransition

    var body: some View {
        GeometryReader { proxy in
            let dividerWidth: CGFloat = 1
            let availableWidth = max(proxy.size.width - dividerWidth, 0)
            let paneWidths = HomeSplitMetrics.paneWidths(for: availableWidth)

            HStack(spacing: 0) {
                conversationPane
                    .frame(width: paneWidths.chat, height: proxy.size.height)

                Divider()

                InspirationPanel()
                    .frame(width: paneWidths.inspiration, height: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryPanelBackground)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: isEmptyState)
    }

    @ViewBuilder
    private var conversationPane: some View {
        if isEmptyState {
            emptyStateView
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
        } else {
            chatConversationView
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
        }
    }

    private var chatConversationView: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        ChatBubbleView(
                            message: message,
                            onToggleTrace: {
                                viewModel.toggleTrace(messageId: message.id)
                            },
                            onWikiLinkTap: handleWikiLinkTap(_:),
                            onErrorAction: { action in
                                viewModel.handleErrorAction(action, appState: appState)
                            }
                        )
                    }
                }
                .padding(24)
            }
            .background(Theme.primaryPanelBackground)

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
                RunningStatusText(
                    text: statusText,
                    isActive: displayState.shouldAnimateStatusText,
                    font: .system(size: 12),
                    color: Theme.textTertiary
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }

            ChatInputView(
                text: $viewModel.inputText,
                placeholder: inputPlaceholder,
                isDisabled: isInputDisabled,
                showsStopButton: viewModel.isSending,
                isStopping: viewModel.isStopping,
                style: .docked,
                helperText: nil,
                autofocus: true,
                externalRequest: viewModel.chatInputExternalRequest,
                onExternalRequestHandled: {
                    viewModel.consumeChatInputExternalRequest()
                },
                onRequestFileUpload: nil,
                onRequestPodcastPrompt: {
                    viewModel.preparePodcastPrompt()
                },
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryPanelBackground)
    }

    private var emptyStateView: some View {
        @Bindable var viewModel = viewModel

        return GeometryReader { proxy in
            let contentWidth = HomeEmptyStateLayoutMetrics.contentWidth(for: proxy.size.width)

            ScrollView(.vertical) {
                VStack(spacing: HomeEmptyStateLayoutMetrics.sectionSpacing) {
                    PikiLogo(style: .hero)
                        .popoverTip(HomeTip())

                    if !onboardingVM.showcaseDismissed {
                        UseCaseShowcase(
                            items: UseCaseItem.allCases,
                            onSelect: { item in
                                viewModel.inputText = item.starterPrompt
                            },
                            onDismiss: {
                                onboardingVM.dismissShowcase()
                            }
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ChatInputView(
                            text: $viewModel.inputText,
                            placeholder: inputPlaceholder,
                            isDisabled: isInputDisabled,
                            showsStopButton: viewModel.isSending,
                            isStopping: viewModel.isStopping,
                            style: .hero,
                            helperText: emptyStateHint,
                            autofocus: true,
                            externalRequest: viewModel.chatInputExternalRequest,
                            onExternalRequestHandled: {
                                viewModel.consumeChatInputExternalRequest()
                            },
                            onRequestFileUpload: nil,
                            onRequestPodcastPrompt: {
                                viewModel.preparePodcastPrompt()
                            },
                            onSend: { text, files in
                                viewModel.sendMessage(text, appState: appState, selectedFiles: files)
                            },
                            onStop: {
                                viewModel.stopCurrentTask(appState: appState)
                            }
                        )
                        .matchedGeometryEffect(id: "home-input-shell", in: inputTransition)
                    }
                }
                .frame(width: contentWidth)
                .padding(.vertical, HomeEmptyStateLayoutMetrics.verticalPadding)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryPanelBackground)
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
