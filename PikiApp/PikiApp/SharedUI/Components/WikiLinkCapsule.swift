import SwiftUI

struct WikiLinkCapsule: View {
    let target: WikiLinkTarget
    let isEnabled: Bool
    let action: (() -> Void)?

    init(target: WikiLinkTarget, isEnabled: Bool = true, action: (() -> Void)? = nil) {
        self.target = target
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: { action?() }) {
            Text(target.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isEnabled ? target.category.tint : Theme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isEnabled ? target.category.tintBackground : Theme.surfaceSecondary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || action == nil)
        .help(target.rawTarget)
    }
}
