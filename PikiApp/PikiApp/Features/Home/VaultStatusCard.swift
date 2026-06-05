import SwiftUI

struct VaultStatusCard: View {
    let status: ServiceConnectionStatus
    let vaultURL: URL?

    var body: some View {
        let stats = VaultStats(vaultURL: vaultURL, status: status)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vault Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 16) {
                StatItem(label: "Pages", value: "\(stats.pages)")
                StatItem(label: "Sources", value: "\(stats.sources)")
                StatItem(label: "Health", value: stats.health)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var statusColor: Color {
        switch status {
        case .starting: Theme.warning
        case .connected: Theme.success
        case .disconnected: Theme.error
        case .error: Theme.error
        }
    }
}

struct VaultStats {
    let pages: Int
    let sources: Int
    let health: String

    init(vaultURL: URL?, status: ServiceConnectionStatus) {
        guard let vaultURL else {
            pages = 0
            sources = 0
            health = "No vault"
            return
        }

        pages = Self.countMarkdownFiles(in: vaultURL.appendingPathComponent("wiki", isDirectory: true))
        sources = Self.countSourceFiles(in: vaultURL.appendingPathComponent("raw/sources", isDirectory: true))
        health = switch status {
        case .connected: "OK"
        case .starting: "Starting"
        case .disconnected: "Offline"
        case .error: "Error"
        }
    }

    private static func countMarkdownFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" && isRegularFile($0) }
            .count
    }

    private static func countSourceFiles(in directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return urls.filter { isRegularFile($0) }.count
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct RecentActivityList: View {
    let entries: [ActivityEntry]
    let onRollback: (ActivityEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if entries.isEmpty {
                Text("No recent activity")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    ActivityRow(entry: entry, onRollback: { onRollback(entry) })
                }
            }
        }
    }
}
