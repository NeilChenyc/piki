import AppKit
import SwiftUI

struct MarkdownSelectableTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    init(attributedText: NSAttributedString, onOpenWikiLink: ((WikiLinkTarget) -> Void)? = nil) {
        self.attributedText = attributedText
        self.onOpenWikiLink = onOpenWikiLink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenWikiLink: onOpenWikiLink)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeContainerScrollView()
        let textView = Self.makeConfiguredTextView()
        textView.delegate = context.coordinator
        updateTextView(textView, coordinator: context.coordinator)
        scrollView.documentView = textView
        return scrollView
    }

    static func makeContainerScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    static func makeConfiguredTextView() -> NSTextView {
        let textView = NSTextView(frame: .zero)
        Self.configure(textView)
        return textView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenWikiLink = onOpenWikiLink
        updateTextView(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView else {
            return nil
        }

        let width = proposal.width ?? nsView.bounds.width
        let resolvedWidth = max(width, 1)

        if let textContainer = textView.textContainer, let layoutManager = textView.layoutManager {
            textContainer.containerSize = NSSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = ceil(usedRect.height + textView.textContainerInset.height * 2)
            return CGSize(width: resolvedWidth, height: height)
        }

        return nil
    }

    static func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.textStorage?.setAttributedString(attributedText)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenWikiLink: ((WikiLinkTarget) -> Void)?

        init(onOpenWikiLink: ((WikiLinkTarget) -> Void)?) {
            self.onOpenWikiLink = onOpenWikiLink
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?

            if let directURL = link as? URL {
                url = directURL
            } else if let string = link as? String {
                url = URL(string: string)
            } else {
                url = nil
            }

            guard let url, let target = WikiLinkTarget(url: url), let onOpenWikiLink else {
                return false
            }

            onOpenWikiLink(target)
            return true
        }
    }
}
