import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            ServiceURLSettingsSection()
        }
        .frame(width: 400, height: 180)
        .padding()
    }
}

struct ServiceURLSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var urlString = "http://127.0.0.1:8000"

    var body: some View {
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
                    Task { await testConnection() }
                }
            }

            if let message = appState.serviceErrorMessage, !appState.isConnected {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
            }
        }
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
}
