import SwiftUI

@Observable
@MainActor
final class WikiViewModel {
    var categories: [WikiCategory] = WikiCategory.defaults
    var selectedPage: WikiPage?
    var searchQuery: String = ""
    var errorMessage: String?
    var isLoading = false

    private var loadedVaultPath: String?

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

    func loadWiki(vaultURL: URL?) async {
        guard let vaultURL else {
            errorMessage = "No vault selected."
            categories = WikiCategory.defaults
            selectedPage = nil
            return
        }

        isLoading = true
        let wikiURL = vaultURL.appendingPathComponent("wiki", isDirectory: true)
        let loaded = await Task.detached {
            Self.loadAllCategories(wikiURL: wikiURL)
        }.value

        guard !Task.isCancelled else {
            loadedVaultPath = nil
            isLoading = false
            return
        }

        categories = loaded
        if selectedPage == nil {
            selectedPage = loaded.flatMap(\.pages).first
        }
        errorMessage = nil
        isLoading = false
    }

    @discardableResult
    func selectPage(for target: WikiLinkTarget) -> Bool {
        guard let page = page(for: target) else { return false }
        selectedPage = page
        return true
    }

    func page(for target: WikiLinkTarget) -> WikiPage? {
        categories
            .flatMap(\.pages)
            .first { $0.selectionKey == target.selectionKey }
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
                return WikiPage(
                    id: url.path(percentEncoded: false),
                    title: pageTitle(for: url, content: content),
                    category: category.id,
                    filePath: url.path(percentEncoded: false),
                    content: content,
                    relatedConcepts: extractWikiLinks(from: content),
                    lastModified: modificationDate(for: url)
                )
            }
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
