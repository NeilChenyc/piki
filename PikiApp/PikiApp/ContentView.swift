import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
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
        .background(Theme.surfaceBackground)
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
