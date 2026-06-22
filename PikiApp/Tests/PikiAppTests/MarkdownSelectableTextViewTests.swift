import AppKit
import Testing
@testable import PikiApp

@Suite("Markdown selectable text view")
struct MarkdownSelectableTextViewTests {
    @MainActor
    @Test
    func configuresNativeTextViewForSelectionAndLinks() {
        let textView = NSTextView(frame: .zero)

        MarkdownSelectableTextView.configure(textView)

        #expect(textView.isEditable == false)
        #expect(textView.isSelectable)
        #expect(textView.drawsBackground == false)
        #expect(textView.textContainer?.widthTracksTextView == true)
        #expect(textView.linkTextAttributes?[.underlineStyle] != nil)
    }
}
