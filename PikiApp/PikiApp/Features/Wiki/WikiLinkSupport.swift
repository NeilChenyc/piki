import SwiftUI

enum WikiLinkCategory: String, CaseIterable, Equatable, Hashable {
    case sources
    case concepts
    case entities
    case domains
    case synthesis

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "sources":
            self = .sources
        case "concepts":
            self = .concepts
        case "entities":
            self = .entities
        case "domains":
            self = .domains
        case "synthesis":
            self = .synthesis
        default:
            return nil
        }
    }

    var tint: Color {
        switch self {
        case .sources:
            return Color(red: 61 / 255, green: 128 / 255, blue: 246 / 255)
        case .concepts:
            return Color(red: 120 / 255, green: 85 / 255, blue: 255 / 255)
        case .entities:
            return Color(red: 226 / 255, green: 113 / 255, blue: 49 / 255)
        case .domains:
            return Color(red: 44 / 255, green: 150 / 255, blue: 120 / 255)
        case .synthesis:
            return Color(red: 191 / 255, green: 73 / 255, blue: 135 / 255)
        }
    }

    var tintBackground: Color {
        tint.opacity(0.12)
    }
}

struct WikiLinkTarget: Equatable, Hashable {
    let rawTarget: String
    let category: WikiLinkCategory
    let slug: String
    let displayTitle: String

    init(rawTarget: String, category: WikiLinkCategory, slug: String, displayTitle: String) {
        self.rawTarget = rawTarget
        self.category = category
        self.slug = slug
        self.displayTitle = displayTitle
    }

    init?(rawMarkup: String) {
        let trimmed = rawMarkup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pieces = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let targetPart = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPart = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let pathComponents = targetPart.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard pathComponents.count == 2, let category = WikiLinkCategory(rawValue: String(pathComponents[0])) else {
            return nil
        }

        let slug = String(pathComponents[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }

        self.init(
            rawTarget: "\(category.rawValue)/\(slug)",
            category: category,
            slug: slug,
            displayTitle: displayPart.isEmpty ? slug : displayPart
        )
    }

    init?(url: URL) {
        guard url.scheme == WikiLinkParser.urlScheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let targetValue = components.queryItems?.first(where: { $0.name == "target" })?.value else {
            return nil
        }

        let displayValue = components.queryItems?.first(where: { $0.name == "display" })?.value
        if let parsed = WikiLinkTarget(rawMarkup: displayValue.map { "\(targetValue)|\($0)" } ?? targetValue) {
            self = parsed
        } else {
            return nil
        }
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = WikiLinkParser.urlScheme
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "target", value: rawTarget),
            URLQueryItem(name: "display", value: displayTitle),
        ]
        return components.url
    }
}

enum WikiInlineSegment: Equatable {
    case markdown(String)
    case wikiLink(WikiLinkTarget)
}

enum WikiLinkParser {
    static let urlScheme = "piki-wiki"

    static func parseInlineSegments(_ source: String) -> [WikiInlineSegment] {
        guard !source.isEmpty else { return [] }

        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.markdown(source)]
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)
        guard !matches.isEmpty else {
            return [.markdown(source)]
        }

        var segments: [WikiInlineSegment] = []
        var currentLocation = source.startIndex

        for match in matches {
            guard
                let matchRange = Range(match.range, in: source),
                let contentRange = Range(match.range(at: 1), in: source)
            else {
                continue
            }

            if currentLocation < matchRange.lowerBound {
                segments.append(.markdown(String(source[currentLocation..<matchRange.lowerBound])))
            }

            let rawMarkup = String(source[contentRange])
            if let target = WikiLinkTarget(rawMarkup: rawMarkup) {
                segments.append(.wikiLink(target))
            } else {
                segments.append(.markdown(String(source[matchRange])))
            }

            currentLocation = matchRange.upperBound
        }

        if currentLocation < source.endIndex {
            segments.append(.markdown(String(source[currentLocation..<source.endIndex])))
        }

        return segments.filter {
            switch $0 {
            case .markdown(let text):
                return !text.isEmpty
            case .wikiLink:
                return true
            }
        }
    }

    static func extractUniqueTargets(from source: String) -> [WikiLinkTarget] {
        var seen: Set<WikiLinkTarget> = []
        var targets: [WikiLinkTarget] = []

        for segment in parseInlineSegments(source) {
            guard case .wikiLink(let target) = segment else { continue }
            if seen.insert(target).inserted {
                targets.append(target)
            }
        }

        return targets.sorted { $0.rawTarget.localizedStandardCompare($1.rawTarget) == .orderedAscending }
    }

    static func rewriteMarkdownPreservingWikiLinks(_ source: String) -> String {
        parseInlineSegments(source)
            .map { segment in
                switch segment {
                case .markdown(let text):
                    return text
                case .wikiLink(let target):
                    let label = escapeMarkdownLabel(target.displayTitle)
                    return "[\(label)](\(target.url?.absoluteString ?? ""))"
                }
            }
            .joined()
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

extension WikiLinkTarget {
    var selectionKey: String {
        "\(category.rawValue)/\(slug)"
    }
}
