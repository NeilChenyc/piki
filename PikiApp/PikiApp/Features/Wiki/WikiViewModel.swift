import SwiftUI

@Observable
@MainActor
final class WikiViewModel {
    var categories: [WikiCategory] = WikiCategory.defaults
    var selectedPage: WikiPage?
    var searchQuery: String = ""
    var errorMessage: String?

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

    func loadWiki(vaultURL: URL?) {
        guard let vaultURL else {
            errorMessage = "No vault selected."
            categories = WikiCategory.defaults
            selectedPage = nil
            return
        }

        let wikiURL = vaultURL.appendingPathComponent("wiki", isDirectory: true)
        let loadedCategories = WikiCategory.defaults.map { category in
            var mutable = category
            mutable.pages = loadPages(category: category, wikiURL: wikiURL)
            return mutable
        }

        categories = loadedCategories
        if selectedPage == nil {
            selectedPage = loadedCategories.flatMap(\.pages).first
        }
        errorMessage = nil
    }

    private func loadPages(category: WikiCategory, wikiURL: URL) -> [WikiPage] {
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
                    title: title(for: url, content: content),
                    category: category.id,
                    filePath: url.path(percentEncoded: false),
                    content: content,
                    relatedConcepts: extractWikiLinks(from: content),
                    lastModified: modificationDate(for: url)
                )
            }
    }

    private func title(for url: URL, content: String) -> String {
        if let heading = content
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func extractWikiLinks(from content: String) -> [String] {
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)
        let links = matches.compactMap { match -> String? in
            guard let linkRange = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[linkRange]).components(separatedBy: "|").first
        }
        return Array(Set(links)).sorted()
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
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
    var relatedConcepts: [String] = []
    var lastModified: Date = Date()
}
