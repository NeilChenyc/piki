import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            ServiceRuntimeSettingsSection()
        }
        .frame(width: 400, height: 120)
        .padding()
    }
}

struct ServiceRuntimeSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Runtime Host") {
            HStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(appState.connectionStatus.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Test Runtime") {
                    Task { await testConnection() }
                }
            }

            if let message = appState.serviceErrorMessage, !appState.isConnected {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
            }
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
        await appState.serviceManager?.testConnection()
    }
}
