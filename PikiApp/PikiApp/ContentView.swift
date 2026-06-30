import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
        } detail: {
            Group {
                switch appState.selectedTab {
                case .home:
                    HomeView()
                case .inbox:
                    InboxView()
                case .wiki:
                    WikiView()
                case .health:
                    HealthView()
                case .settings:
                    RuntimeSettingsView()
                }
            }
            .background(Theme.primaryPanelBackground)
        }
        .background(Theme.appBackground)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(HomeViewModel())
        .environment(WikiViewModel())
        .environment(InboxViewModel())
        .environment(HealthViewModel())
        .environment(RuntimeSettingsViewModel())
}
