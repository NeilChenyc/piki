import CoreGraphics

enum DetailLayoutGuide {
    static let sidebarIdealWidth: CGFloat = 220
    static let homeAuxiliaryWidth: CGFloat = 280
    static let wikiSidebarIdealWidth: CGFloat = 240
    static let wikiSidebarMaxWidth: CGFloat = 280
    static let inboxPrimaryIdealWidth: CGFloat = 500
    static let inboxSecondaryIdealWidth: CGFloat = 500
    static let healthSidebarIdealWidth: CGFloat = 340

    static let inboxPrimaryMinWidth: CGFloat? = nil
    static let inboxSecondaryMinWidth: CGFloat? = nil
    static let healthContentMinWidth: CGFloat? = nil

    static let healthUsesSingleColumnLayout = true
    static let inboxUsesPersistentDetailPane = true
    static let inboxListUsesBoundedScrollViewport = true
}
