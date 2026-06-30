import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: DetailLayoutGuide.sidebarIdealWidth,
                    ideal: DetailLayoutGuide.sidebarIdealWidth,
                    max: DetailLayoutGuide.sidebarIdealWidth
                )
        } detail: {
            ZStack {
                Theme.primaryPanelBackground
                    .ignoresSafeArea()

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
