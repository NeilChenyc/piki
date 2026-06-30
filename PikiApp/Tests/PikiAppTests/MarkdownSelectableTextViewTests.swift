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

    @MainActor
    @Test
    func embedsConfiguredTextViewInsideScrollContainer() {
        let scrollView = MarkdownSelectableTextView.makeContainerScrollView()
        let textView = MarkdownSelectableTextView.makeConfiguredTextView()
        scrollView.documentView = textView

        #expect(scrollView.drawsBackground == false)
        #expect(scrollView.hasVerticalScroller == false)
        #expect(scrollView.documentView is NSTextView)
        #expect(textView.isSelectable)
        #expect(textView.isEditable == false)
    }
}
