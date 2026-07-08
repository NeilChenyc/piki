import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(OnboardingViewModel.self) private var onboardingVM
    @Environment(RuntimeSettingsViewModel.self) private var runtimeSettingsVM

    var body: some View {
        @Bindable var appState = appState
        @Bindable var onboardingVM = onboardingVM

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
        .sheet(isPresented: $onboardingVM.showWizard) {
            SetupWizardSheet(viewModel: onboardingVM)
                .interactiveDismissDisabled()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(HomeViewModel())
        .environment(WikiViewModel())
        .environment(InboxViewModel())
        .environment(HealthViewModel())
        .environment(InspirationViewModel())
        .environment(RuntimeSettingsViewModel())
        .environment(OnboardingViewModel())
}
