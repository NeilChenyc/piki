import SwiftUI

struct ActivityRow: View {
    let entry: ActivityEntry
    let onRollback: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(iconColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .relative(presentation: .named))
                    if !entry.status.isEmpty {
                        Text(entry.status)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if entry.canRollback {
                Button(action: onRollback) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Rollback this vault change")
            }
        }
    }

    private var iconColor: Color {
        switch entry.type {
        case .ingest: Theme.primary
        case .query: .blue
        case .lint: .orange
        case .rollback: .purple
        }
    }
}
