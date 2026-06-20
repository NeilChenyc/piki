import SwiftUI

struct PresetCard: View {
    let preset: ConfigurationPreset
    let isActive: Bool
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onApply) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.accentDark)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accentLight)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }

                Text(preset.agentModel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                if !preset.anthropicBaseURL.isEmpty {
                    Text(preset.anthropicBaseURL)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Theme.accentLight.opacity(0.3) : Theme.surfaceSecondary)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Theme.accent : Theme.border, lineWidth: isActive ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", action: onEdit)
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}
