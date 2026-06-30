import Testing
@testable import PikiApp

@Suite("Chat input attachment menu state")
struct ChatInputAttachmentMenuStateTests {
    @Test
    func toggleExpandsAndCollapsesMenu() {
        var state = ChatInputAttachmentMenuState()

        state.toggle()
        #expect(state.isExpanded)

        state.toggle()
        #expect(state.isExpanded == false)
    }

    @Test
    func dismissCollapsesMenuWithoutSelectingAction() {
        var state = ChatInputAttachmentMenuState(isExpanded: true)

        let selection = state.dismiss()

        #expect(state.isExpanded == false)
        #expect(selection == nil)
    }

    @Test
    func selectReturnsActionAndCollapsesMenu() {
        var state = ChatInputAttachmentMenuState(isExpanded: true)

        let selection = state.select(.podcastTranscription)

        #expect(selection == .podcastTranscription)
        #expect(state.isExpanded == false)
    }

    @Test
    func selectLocalFileUploadReturnsActionAndCollapsesMenu() {
        var state = ChatInputAttachmentMenuState(isExpanded: true)

        let selection = state.select(.localFileUpload)

        #expect(selection == .localFileUpload)
        #expect(state.isExpanded == false)
    }
}
