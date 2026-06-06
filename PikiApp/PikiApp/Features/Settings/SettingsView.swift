import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text(appState.vaultPath?.path() ?? "No vault selected")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Choose...") {
                        chooseVault()
                    }
                }
            }
        }
        .padding()
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your Piki vault directory"
        if panel.runModal() == .OK, let url = panel.url {
            appState.vaultPath = url
        }
    }
}

struct ConnectionSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var urlString = "http://127.0.0.1:8000"

    var body: some View {
        Form {
            Section("Agent Service") {
                TextField("Service URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                    Text(appState.connectionStatus.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Test Connection") {
                        Task {
                            await testConnection()
                        }
                    }
                }

                if let message = appState.serviceErrorMessage, !appState.isConnected {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.error)
                }
            }

            if let health = appState.serviceHealth {
                Section("Runtime") {
                    SettingsInfoRow(label: "Mode", value: appState.runtimeModeTitle)
                    SettingsInfoRow(label: "Provider", value: health.provider?.isEmpty == false ? health.provider! : "--")
                    SettingsInfoRow(label: "Runtime enabled", value: boolText(health.agentRuntimeEnabled))
                    SettingsInfoRow(label: "Runtime configured", value: boolText(health.agentRuntimeConfigured))
                    SettingsInfoRow(label: "API key", value: boolText(health.anthropicAPIKeyConfigured))
                    SettingsInfoRow(label: "Model", value: health.agentModel?.isEmpty == false ? health.agentModel! : "--")
                    SettingsInfoRow(label: "Config dir", value: health.claudeConfigDir?.isEmpty == false ? health.claudeConfigDir! : "--")
                    Text(appState.runtimeModeDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding()
        .onAppear {
            urlString = appState.serviceBaseURL.absoluteString
        }
    }

    private var connectionColor: Color {
        switch appState.connectionStatus {
        case .starting: Theme.warning
        case .connected: Theme.success
        case .disconnected: Theme.error
        case .error: Theme.error
        }
    }

    private func testConnection() async {
        if let url = URL(string: urlString) {
            appState.updateServiceBaseURL(url)
        }
        await appState.serviceManager?.testConnection()
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "--" }
        return value ? "Yes" : "No"
    }
}

struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
    }
}
