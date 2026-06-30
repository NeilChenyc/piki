import SwiftUI

enum SidebarGreetingContent {
    static let title = "Hi"
    static let message = "今天收获了什么？"
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SidebarGreetingContent.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .tracking(-0.6)

                Text(SidebarGreetingContent.message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            // Navigation items
            VStack(spacing: 4) {
                ForEach(SidebarTab.allCases) { tab in
                    SidebarNavRow(
                        tab: tab,
                        isSelected: appState.selectedTab == tab
                    ) {
                        state.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Connection status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                    Text(appState.connectionStatus.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                Text(appState.runtimeModeTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(
            minWidth: DetailLayoutGuide.sidebarIdealWidth,
            idealWidth: DetailLayoutGuide.sidebarIdealWidth,
            maxWidth: DetailLayoutGuide.sidebarIdealWidth
        )
        .background(Theme.secondaryPanelBackground)
    }

    private var connectionColor: Color {
        switch appState.connectionStatus {
        case .starting: Theme.warning
        case .connected: Theme.primary
        case .disconnected: Theme.error
        case .error: Theme.error
        }
    }
}
