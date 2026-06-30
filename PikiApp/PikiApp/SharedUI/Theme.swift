import SwiftUI

struct Theme {
    // MARK: - Brand (保留绿色，极度克制使用)
    static let accent = Color(red: 76/255, green: 175/255, blue: 80/255)
    static let accentLight = Color(red: 232/255, green: 245/255, blue: 233/255)
    static let accentDark = Color(red: 46/255, green: 125/255, blue: 50/255)

    // MARK: - Surfaces
    static let appBackground = Color(red: 241/255, green: 241/255, blue: 243/255)
    static let primaryPanelBackground = Color.white
    static let secondaryPanelBackground = Color(red: 244/255, green: 244/255, blue: 246/255)
    static let elevatedCardBackground = Color.white
    static let subtleFill = Color(red: 236/255, green: 236/255, blue: 239/255)

    // MARK: - Selection
    static let selection = Color(red: 228/255, green: 228/255, blue: 232/255)

    // MARK: - Border
    static let border = Color(red: 232/255, green: 232/255, blue: 234/255)

    // MARK: - Text
    static let textPrimary = Color(red: 26/255, green: 26/255, blue: 26/255)
    static let textSecondary = Color(red: 102/255, green: 102/255, blue: 102/255)
    static let textTertiary = Color(red: 153/255, green: 153/255, blue: 153/255)

    // MARK: - Semantic
    static let success = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let warning = Color(red: 255/255, green: 149/255, blue: 0/255)
    static let error = Color(red: 255/255, green: 59/255, blue: 48/255)

    // MARK: - Layout
    static let cornerRadius: CGFloat = 10
    static let cardShadowRadius: CGFloat = 3
    static let spacing: CGFloat = 8
    static let sidebarWidth: CGFloat = 220

    // MARK: - Aliases (backward compat)
    static let primary = accent
    static let primaryDark = accentDark
    static let primaryLight = accentLight
    static let surfaceBackground = appBackground
    static let sidebarBackground = secondaryPanelBackground
    static let cardBackground = elevatedCardBackground
    static let surfaceSecondary = subtleFill
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(.rect(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: Theme.cardShadowRadius, x: 0, y: 1)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
