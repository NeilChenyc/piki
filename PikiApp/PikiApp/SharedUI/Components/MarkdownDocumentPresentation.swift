import Foundation

struct MarkdownDocumentPresentation {
    enum Mode: Equatable {
        case plain
        case documentPage(displayTitle: String?)
    }

    struct MetadataItem: Equatable {
        let key: String
        let value: String
    }

    struct PreparedDocument: Equatable {
        let bodyMarkdown: String
        let metadata: [MetadataItem]
        let resolvedDisplayTitle: String?
        let shouldRenderTitleInsideDocument: Bool
    }

    static func prepare(source: String, mode: Mode) -> PreparedDocument {
        guard case let .documentPage(displayTitle) = mode else {
            return PreparedDocument(
                bodyMarkdown: source,
                metadata: [],
                resolvedDisplayTitle: nil,
                shouldRenderTitleInsideDocument: false
            )
        }

        let parsed = parseFrontmatter(from: source)
        let effectiveDisplayTitle = displayTitle ?? parsed.metadata.first {
            $0.key.compare("title", options: .caseInsensitive) == .orderedSame
        }?.value
        let metadata = parsed.metadata
            .filter { $0.key.lowercased() != "title" }
            .map { MetadataItem(key: $0.key, value: $0.value) }
        let trimmedBody = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRenderTitleInsideDocument = effectiveDisplayTitle != nil
            && firstLevelOneHeading(in: trimmedBody) == nil

        return PreparedDocument(
            bodyMarkdown: trimmedBody,
            metadata: metadata,
            resolvedDisplayTitle: effectiveDisplayTitle,
            shouldRenderTitleInsideDocument: shouldRenderTitleInsideDocument
        )
    }

    private static func parseFrontmatter(from source: String) -> (metadata: [(key: String, value: String)], body: String) {
        guard source.hasPrefix("---\n") else {
            return ([], source)
        }

        let parts = source.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else {
            return ([], source)
        }

        let rawFrontmatter = String(parts[0].dropFirst(4))
        let body = parts.dropFirst().joined(separator: "\n---\n")

        let metadata = rawFrontmatter
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> (key: String, value: String)? in
                let text = String(line).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, !text.hasPrefix("#"), let separator = text.firstIndex(of: ":") else {
                    return nil
                }

                let key = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = text[text.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return nil }
                return (key: key, value: value)
            }

        return (metadata, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstLevelOneHeading(in body: String) -> String? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBody.hasPrefix("# ") else {
            return nil
        }

        let lines = trimmedBody.split(separator: "\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else {
            return nil
        }

        return String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
