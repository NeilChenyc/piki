import Testing
@testable import PikiApp

@Suite("Piki logo style")
struct PikiLogoStyleTests {
    @Test
    func navigationLogoIsDoubledFromPreviousCompactSize() {
        let style = PikiLogo.Style.navigation

        #expect(style.height >= 56)
    }

    @Test
    func heroLogoIsDoubledFromPreviousCompactSize() {
        let style = PikiLogo.Style.hero

        #expect(style.height >= 120)
    }
}
