import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Logo area
            HStack(spacing: 10) {
                PikiLogo()
                    .frame(width: 28, height: 28)
                Text("Piki")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
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
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
        .background(Theme.sidebarBackground)
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
