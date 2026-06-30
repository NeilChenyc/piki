import SwiftUI

@Observable
@MainActor
final class WikiViewModel {
    private struct WikiPageDraftState {
        var text: String
        var isDirty: Bool
    }

    private enum PreviewScale {
        static let `default`: CGFloat = 1.0
        static let minimum: CGFloat = 0.85
        static let maximum: CGFloat = 1.3
        static let step: CGFloat = 0.1
    }

    var categories: [WikiCategory] = WikiCategory.defaults
    var selectedPage: WikiPage?
    var searchQuery: String = ""
    var errorMessage: String?
    var isLoading = false
    var isRefreshing = false
    var previewTextScale: CGFloat = PreviewScale.default

    private(set) var editingPageID: String?
    private var draftStates: [String: WikiPageDraftState] = [:]

    private var loadedVaultPath: String?

    var isEditingSelectedPage: Bool {
        editingPageID == selectedPage?.id
    }

    var editingText: String? {
        guard let selectedPage else { return nil }
        return draftStates[selectedPage.id]?.text
    }

    var selectedPageHasUnsavedDraft: Bool {
        guard let selectedPage else { return false }
        return draftStates[selectedPage.id]?.isDirty ?? false
    }

    var canIncreasePreviewTextScale: Bool {
        previewTextScale < PreviewScale.maximum - 0.001
    }

    var canDecreasePreviewTextScale: Bool {
        previewTextScale > PreviewScale.minimum + 0.001
    }

    var shouldAutoRefresh: Bool {
        !isEditingSelectedPage && !selectedPageHasUnsavedDraft
    }

    var isRefreshInFlight: Bool {
        isLoading || isRefreshing
    }

    var filteredCategories: [WikiCategory] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.map { category in
            var filtered = category
            filtered.pages = category.pages.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.content.localizedCaseInsensitiveContains(query)
            }
            return filtered
        }
        .filter { !$0.pages.isEmpty }
    }

    func loadIfNeeded(vaultURL: URL?) async {
        let path = vaultURL?.path(percentEncoded: false)
        guard path != loadedVaultPath else { return }
        loadedVaultPath = path
        await loadWiki(vaultURL: vaultURL)
    }

    func refreshWikiIfSafe(vaultURL: URL?) async {
        guard shouldAutoRefresh else { return }
        await refreshWiki(vaultURL: vaultURL)
    }

    func syncVisibleWiki(vaultURL: URL?) async {
        let path = vaultURL?.path(percentEncoded: false)
        if path != loadedVaultPath {
            await loadIfNeeded(vaultURL: vaultURL)
        } else {
            await refreshWikiIfSafe(vaultURL: vaultURL)
        }
    }

    func refreshWiki(vaultURL: URL?) async {
        await loadWiki(vaultURL: vaultURL, preservesVisibleContent: true)
    }

    func loadWiki(vaultURL: URL?, preservesVisibleContent: Bool = false) async {
        guard let vaultURL else {
            errorMessage = "No vault selected."
            categories = WikiCategory.defaults
            selectedPage = nil
            isLoading = false
            isRefreshing = false
            return
        }

        let hasVisibleContent = categories.contains(where: { !$0.pages.isEmpty })
        let selectedPageID = selectedPage?.id

        if preservesVisibleContent && hasVisibleContent {
            isRefreshing = true
        } else {
            isLoading = true
        }

        let wikiURL = vaultURL.appendingPathComponent("wiki", isDirectory: true)
        let loaded = await Task.detached {
            Self.loadAllCategories(wikiURL: wikiURL)
        }.value

        guard !Task.isCancelled else {
            loadedVaultPath = nil
            isLoading = false
            isRefreshing = false
            return
        }

        categories = loaded
        selectedPage = Self.reboundSelection(for: selectedPageID, categories: loaded)
        errorMessage = nil
        isLoading = false
        isRefreshing = false
    }

    @discardableResult
    func selectPage(for target: WikiLinkTarget) -> Bool {
        guard let page = page(for: target) else { return false }
        stopEditingSelectedPagePreservingDraft()
        selectedPage = page
        return true
    }

    func page(for target: WikiLinkTarget) -> WikiPage? {
        categories
            .flatMap(\.pages)
            .first { $0.selectionKey == target.selectionKey }
    }

    func startEditingSelectedPage() {
        guard let selectedPage else { return }
        let existingDraft = draftStates[selectedPage.id]
        draftStates[selectedPage.id] = WikiPageDraftState(
            text: existingDraft?.text ?? selectedPage.content,
            isDirty: existingDraft?.isDirty ?? false
        )
        editingPageID = selectedPage.id
    }

    func updateDraftForSelectedPage(_ text: String) {
        guard let selectedPage else { return }
        let baseline = selectedPage.content
        draftStates[selectedPage.id] = WikiPageDraftState(
            text: text,
            isDirty: text != baseline
        )
    }

    func stopEditingSelectedPagePreservingDraft() {
        editingPageID = nil
    }

    func cancelEditingSelectedPage() {
        guard let selectedPage else { return }
        draftStates.removeValue(forKey: selectedPage.id)
        editingPageID = nil
    }

    func saveEditingSelectedPage() throws {
        guard let selectedPage,
              let draft = draftStates[selectedPage.id] else { return }

        let fileURL = URL(fileURLWithPath: selectedPage.filePath)
        try draft.text.write(to: fileURL, atomically: true, encoding: .utf8)

        let refreshed = Self.refresh(page: selectedPage, content: draft.text)
        replace(page: refreshed)
        self.selectedPage = refreshed
        draftStates.removeValue(forKey: selectedPage.id)
        editingPageID = nil
    }

    func increasePreviewTextScale() {
        previewTextScale = min(PreviewScale.maximum, roundedScale(previewTextScale + PreviewScale.step))
    }

    func decreasePreviewTextScale() {
        previewTextScale = max(PreviewScale.minimum, roundedScale(previewTextScale - PreviewScale.step))
    }

    private func replace(page updatedPage: WikiPage) {
        for categoryIndex in categories.indices {
            if let pageIndex = categories[categoryIndex].pages.firstIndex(where: { $0.id == updatedPage.id }) {
                categories[categoryIndex].pages[pageIndex] = updatedPage
                return
            }
        }
    }

    private func roundedScale(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100
    }

    private nonisolated static func reboundSelection(for pageID: String?, categories: [WikiCategory]) -> WikiPage? {
        let pages = categories.flatMap(\.pages)
        guard let pageID else { return pages.first }
        return pages.first(where: { $0.id == pageID }) ?? pages.first
    }

    private nonisolated static func loadAllCategories(wikiURL: URL) -> [WikiCategory] {
        WikiCategory.defaults.map { category in
            var mutable = category
            mutable.pages = loadPages(category: category, wikiURL: wikiURL)
            return mutable
        }
    }

    private nonisolated static func loadPages(category: WikiCategory, wikiURL: URL) -> [WikiPage] {
        let directory = wikiURL.appendingPathComponent(category.id, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "md" && isRegularFile($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return makePage(categoryID: category.id, url: url, content: content)
            }
    }

    private nonisolated static func makePage(categoryID: String, url: URL, content: String) -> WikiPage {
        WikiPage(
            id: url.path(percentEncoded: false),
            title: pageTitle(for: url, content: content),
            category: categoryID,
            filePath: url.path(percentEncoded: false),
            content: content,
            relatedConcepts: extractWikiLinks(from: content),
            lastModified: modificationDate(for: url)
        )
    }

    private nonisolated static func refresh(page: WikiPage, content: String) -> WikiPage {
        let fileURL = URL(fileURLWithPath: page.filePath)
        return WikiPage(
            id: page.id,
            title: pageTitle(for: fileURL, content: content),
            category: page.category,
            filePath: page.filePath,
            content: content,
            relatedConcepts: extractWikiLinks(from: content),
            lastModified: modificationDate(for: fileURL)
        )
    }

    private nonisolated static func pageTitle(for url: URL, content: String) -> String {
        if let frontmatterTitle = frontmatterTitle(in: content) {
            return frontmatterTitle
        }
        if let heading = content
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private nonisolated static func extractWikiLinks(from content: String) -> [WikiLinkTarget] {
        WikiLinkParser.extractUniqueTargets(from: content)
    }

    private nonisolated static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private nonisolated static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private nonisolated static func frontmatterTitle(in content: String) -> String? {
        guard content.hasPrefix("---\n") else { return nil }
        guard let closingRange = content.range(of: "\n---\n") else { return nil }

        let frontmatter = content[content.index(content.startIndex, offsetBy: 4)..<closingRange.lowerBound]
        for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.lowercased().hasPrefix("title:") else { continue }
            let value = text.dropFirst("title:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return nil
    }
}

struct WikiCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    var pages: [WikiPage]
    var isExpanded: Bool = true

    static let defaults: [WikiCategory] = [
        WikiCategory(id: "sources", title: "Sources", icon: "doc.text", pages: []),
        WikiCategory(id: "concepts", title: "Concepts", icon: "lightbulb", pages: []),
        WikiCategory(id: "entities", title: "Entities", icon: "person.2", pages: []),
        WikiCategory(id: "domains", title: "Domains", icon: "globe", pages: []),
        WikiCategory(id: "synthesis", title: "Synthesis", icon: "arrow.triangle.merge", pages: []),
    ]
}

struct WikiPage: Identifiable {
    let id: String
    let title: String
    let category: String
    let filePath: String
    var content: String = ""
    var relatedConcepts: [WikiLinkTarget] = []
    var lastModified: Date = Date()

    var selectionKey: String {
        let slug = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        return "\(category)/\(slug)"
    }
}
