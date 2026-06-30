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

        #expect(hero.minHeight <= 82)
        #expect(hero.textSize < 21)
    }
}
