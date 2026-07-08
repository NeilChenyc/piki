import Testing
@testable import PikiApp

@Suite("Layout stability")
struct LayoutStabilityTests {
    @Test
    func detailLayoutGuideAvoidsHardMinimumWidthsThatForceSplitViewReflow() {
        #expect(DetailLayoutGuide.inboxPrimaryMinWidth == nil)
        #expect(DetailLayoutGuide.inboxSecondaryMinWidth == nil)
        #expect(DetailLayoutGuide.healthContentMinWidth == nil)
    }

    @Test
    func detailLayoutGuideKeepsStableIdealPaneWidths() {
        #expect(DetailLayoutGuide.sidebarIdealWidth == 220)
        #expect(DetailLayoutGuide.homeAuxiliaryWidth == 280)
        #expect(DetailLayoutGuide.wikiSidebarIdealWidth == 240)
        #expect(DetailLayoutGuide.inboxPrimaryIdealWidth == 500)
        #expect(DetailLayoutGuide.inboxSecondaryIdealWidth == 500)
    }

    @Test
    func detailLayoutGuideMarksStabilityCriticalLayoutPolicies() {
        #expect(DetailLayoutGuide.healthUsesSingleColumnLayout)
        #expect(DetailLayoutGuide.inboxUsesPersistentDetailPane)
        #expect(DetailLayoutGuide.inboxListUsesBoundedScrollViewport)
    }

    @Test
    func homeEmptyStateContentUsesACompactBoundedWorkArea() {
        #expect(HomeEmptyStateLayoutMetrics.maxContentWidth <= 720)
        #expect(HomeEmptyStateLayoutMetrics.horizontalPadding <= 32)
        #expect(HomeEmptyStateLayoutMetrics.contentWidth(for: 620) == 572)
        #expect(HomeEmptyStateLayoutMetrics.contentWidth(for: 960) == HomeEmptyStateLayoutMetrics.maxContentWidth)
    }

    @Test
    func homeStarterUseCaseCardsStayCompactEnoughForTheChatPane() {
        #expect(UseCaseCardMetrics.minWidth <= 148)
        #expect(UseCaseCardMetrics.maxWidth <= 168)
        #expect(UseCaseCardMetrics.minHeight <= 96)
        #expect(UseCaseCardMetrics.iconSize <= 20)
    }
}
