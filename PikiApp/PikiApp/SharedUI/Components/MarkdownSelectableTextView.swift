import AppKit
import SwiftUI

struct MarkdownSelectableTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let layoutWidth: CGFloat?
    let onOpenWikiLink: ((WikiLinkTarget) -> Void)?

    init(
        attributedText: NSAttributedString,
        layoutWidth: CGFloat? = nil,
        onOpenWikiLink: ((WikiLinkTarget) -> Void)? = nil
    ) {
        self.attributedText = attributedText
        self.layoutWidth = layoutWidth
        self.onOpenWikiLink = onOpenWikiLink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenWikiLink: onOpenWikiLink)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = Self.makeConfiguredTextView()
        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    static func makeConfiguredTextView() -> NSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(
            width: 1,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        Self.configure(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onOpenWikiLink = onOpenWikiLink
        updateTextView(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = Self.measurementWidth(
            proposalWidth: proposal.width,
            layoutWidth: layoutWidth,
            currentWidth: nsView.bounds.width,
            lastKnownWidth: context.coordinator.lastKnownWidth
        )
        context.coordinator.lastKnownWidth = width
        let height = Self.measuredHeight(for: nsView, width: width)
        return CGSize(width: width, height: max(height, 1))
    }

    static func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.wantsLayer = true
        textView.layer?.masksToBounds = true
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
        textView.textContainer?.lineBreakMode = .byWordWrapping
    }

    static func measurementWidth(
        proposalWidth: CGFloat?,
        layoutWidth: CGFloat? = nil,
        currentWidth: CGFloat,
        lastKnownWidth: CGFloat? = nil
    ) -> CGFloat {
        let candidates = [proposalWidth, layoutWidth].compactMap { value -> CGFloat? in
            guard let value, value > 1 else { return nil }
            return value
        }
        if let measuredWidth = candidates.min() {
            return measuredWidth
        }
        if currentWidth > 1 {
            return currentWidth
        }
        if let lastKnownWidth, lastKnownWidth > 1 {
            return lastKnownWidth
        }
        return 1
    }

    static func shouldUpdateText(existing: NSAttributedString?, incoming: NSAttributedString) -> Bool {
        guard let existing else { return true }
        return existing.isEqual(to: incoming) == false
    }

    static func measuredHeight(for textView: NSTextView, width: CGFloat) -> CGFloat {
        guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else {
            return 1
        }

        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentBottom = max(
            usedRect.maxY,
            layoutManager.extraLineFragmentRect.maxY,
            maximumLineFragmentMaxY(layoutManager: layoutManager)
        )
        return ceil(contentBottom + textView.textContainerInset.height * 2)
    }

    private static func maximumLineFragmentMaxY(layoutManager: NSLayoutManager) -> CGFloat {
        guard layoutManager.numberOfGlyphs > 0 else { return 0 }

        var maxY: CGFloat = 0
        var glyphIndex = 0

        while glyphIndex < layoutManager.numberOfGlyphs {
            var range = NSRange()
            let rect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &range,
                withoutAdditionalLayout: true
            )
            maxY = max(maxY, rect.maxY)
            glyphIndex = NSMaxRange(range)
        }

        return maxY
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        if Self.shouldUpdateText(existing: textView.textStorage, incoming: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenWikiLink: ((WikiLinkTarget) -> Void)?
        var lastKnownWidth: CGFloat?

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
