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
    func producesConfiguredTextViewWithoutInnerScrollContainer() {
        let textView = MarkdownSelectableTextView.makeConfiguredTextView()

        #expect(textView.enclosingScrollView == nil)
        #expect(textView.isSelectable)
        #expect(textView.isEditable == false)
        #expect(textView.textContainerInset == .zero)
        #expect(textView.layer?.masksToBounds == true)
    }

    @MainActor
    @Test
    func prefersFreshProposalWidthWhenPaneExpandsBeyondStaleCurrentWidth() {
        let width = MarkdownSelectableTextView.measurementWidth(
            proposalWidth: 620,
            currentWidth: 603
        )

        #expect(width == 620)
    }

    @MainActor
    @Test
    func fallsBackToCurrentWidthWhenProposalIsUnavailable() {
        let width = MarkdownSelectableTextView.measurementWidth(
            proposalWidth: nil,
            currentWidth: 603
        )

        #expect(width == 603)
    }

    @MainActor
    @Test
    func reusesLastKnownWidthWhenSplitViewTemporarilyReportsZeroWidth() {
        let width = MarkdownSelectableTextView.measurementWidth(
            proposalWidth: nil,
            currentWidth: 0,
            lastKnownWidth: 287
        )

        #expect(width == 287)
    }

    @MainActor
    @Test
    func onlyUpdatesNativeTextWhenAttributedContentChanges() {
        let existing = NSAttributedString(string: "same")
        let incoming = NSAttributedString(string: "same")
        let changed = NSAttributedString(string: "changed")

        #expect(MarkdownSelectableTextView.shouldUpdateText(existing: existing, incoming: incoming) == false)
        #expect(MarkdownSelectableTextView.shouldUpdateText(existing: existing, incoming: changed))
    }

    @MainActor
    @Test
    func measuredHeightAccountsForTrailingExtraLineFragment() {
        let textView = MarkdownSelectableTextView.makeConfiguredTextView()
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: "首行\n第二行\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            )
        )

        let measuredHeight = MarkdownSelectableTextView.measuredHeight(for: textView, width: 320)

        #expect(measuredHeight >= 48)
    }
}
