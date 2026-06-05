import SwiftUI

struct Theme {
    static let primary = Color(red: 76/255, green: 175/255, blue: 80/255)
    static let primaryDark = Color(red: 46/255, green: 125/255, blue: 50/255)
    static let primaryLight = Color(red: 232/255, green: 245/255, blue: 233/255)

    static let surfaceBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    static let cornerRadius: CGFloat = 12
    static let cardShadowRadius: CGFloat = 4
    static let spacing: CGFloat = 8
    static let sidebarWidth: CGFloat = 220
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(.rect(cornerRadius: Theme.cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: Theme.cardShadowRadius, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
