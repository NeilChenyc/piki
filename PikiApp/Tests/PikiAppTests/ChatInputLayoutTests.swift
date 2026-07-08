import Testing
@testable import PikiApp

@Suite("Chat input layout")
struct ChatInputLayoutTests {
    @Test
    func heroLayoutUsesSameActionIconsAsDockedLayout() {
        let hero = ChatInputMetrics(style: .hero)
        let docked = ChatInputMetrics(style: .docked)

        #expect(hero.attachmentSymbolName == docked.attachmentSymbolName)
        #expect(hero.sendSymbolName == docked.sendSymbolName)
    }

    @Test
    func heroLayoutIsMoreCompactThanPreviousOversizedVersion() {
        let hero = ChatInputMetrics(style: .hero)

        #expect(hero.minHeight <= 72)
        #expect(hero.textSize <= 15)
        #expect(hero.cornerRadius <= 18)
        #expect(hero.actionButtonSize <= 30)
    }

    @Test
    func attachmentMenuDismissBackdropStaysWithinLocalBounds() {
        let hero = ChatInputMetrics(style: .hero)
        let docked = ChatInputMetrics(style: .docked)

        #expect(hero.usesFullscreenDismissOverlay == false)
        #expect(docked.usesFullscreenDismissOverlay == false)
    }
}
