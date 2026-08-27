internal import Foundation

/// OPDS 1.2, which is an Atom feed with a handful of extra relations.
///
/// Parsed with `XMLParser` rather than a dependency. Atom is a small grammar and the
/// subset OPDS uses is smaller still — a feed title, entries, and links distinguished by
/// their `rel`. The whole reader is one delegate.
enum OpdsAtom {
    static func parse(_ data: Data, baseURL: URL) throws -> OpdsFeed {
        let reader = Reader(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw OpdsError.malformed(reason: parser.parserError?.localizedDescription ?? "invalid XML")
        }
        guard reader.sawFeed else { throw OpdsError.notAFeed(received: .unrecognised(contentType: nil)) }
        return reader.feed()
    }

    /// Accumulates a feed as the parser walks it.
    ///
    /// A class with mutable state, which is what `XMLParser` requires. Everything it
    /// produces is a value.
    private final class Reader: NSObject, XMLParserDelegate {
        private let baseURL: URL

        private(set) var sawFeed = false

        private var feedTitle = ""
        private var navigation: [OpdsSection] = []
        private var publications: [OpdsEntry] = []
        private var facets: [OpdsFacet] = []
        private var next: URL?
        private var searchTemplate: String?

        /// The entry being read, if the parser is inside one.
        private var entry: PartialEntry?

        /// Text accumulated for the element currently open. Reset on every start, because
        /// `foundCharacters` arrives in arbitrarily many pieces.
        ///
        /// ponytail: a `summary` holding XHTML yields only the run of text after its last
        /// child element. Feeds that do this are rare and the result is a short summary
        /// rather than a wrong one. Read the markup properly if a real catalogue needs it.
        private var text = ""

        /// Where an OpenSearch description lives, when the feed pointed at one instead of
        /// carrying a template. Fetched by the client, which is the part that can.
        private var searchDescription: URL?

        init(baseURL: URL) {
            self.baseURL = baseURL
        }

        func feed() -> OpdsFeed {
            OpdsFeed(
                title: feedTitle,
                navigation: navigation,
                publications: publications,
                facets: facets,
                next: next,
                searchTemplate: searchTemplate,
                searchDescription: searchDescription
            )
        }

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            text = ""
            switch element {
            case "feed":
                sawFeed = true
            case "entry":
                entry = PartialEntry()
            case "link":
                link(attributes)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement element: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if element == "entry" {
                if let finished = entry?.finished() { publications.append(finished) }
                entry = nil
                return
            }
            if entry != nil {
                closeInsideEntry(element, value)
            } else if element == "title", feedTitle.isEmpty {
                feedTitle = value
            }
        }

        /// The elements that mean something only within an `entry`.
        ///
        /// Split from the element handler above because the two together exceeded the
        /// complexity cap, and they were two things anyway: a feed's own fields and an
        /// entry's.
        private func closeInsideEntry(_ element: String, _ value: String) {
            switch element {
            case "title":
                entry?.title = value
            case "id":
                entry?.id = value
            case "name":
                // Inside `author`. Atom puts nothing else called `name` in a feed.
                if !value.isEmpty { entry?.authors.append(value) }
            case "summary", "content":
                if entry?.summary == nil, !value.isEmpty { entry?.summary = value }
            case "updated":
                entry?.updated = OpdsDates.parse(value)
            case "series":
                // Calibre's OPDS extension. Named `series` in its own namespace, which
                // namespace processing has already stripped.
                if !value.isEmpty { entry?.series = value }
            default:
                break
            }
        }

        /// An attribute by its local name, whether or not the parser kept its prefix.
        ///
        /// `count`, `facetGroup` and `activeFacet` all live in namespaces, and namespace
        /// processing does not strip a prefix from an *attribute* name the way it does from
        /// an element. So `opds:count` arrives spelled that way, and a lookup for `count`
        /// finds nothing — which is how a section that declared twelve items reported none.
        private static func attribute(_ name: String, in attributes: [String: String]) -> String? {
            if let exact = attributes[name] { return exact }
            return attributes.first { $0.key.hasSuffix(":" + name) }?.value
        }

        /// A `link`, which in OPDS carries almost everything.
        private func link(_ attributes: [String: String]) {
            guard let raw = attributes["href"],
                  let href = OpdsDocument.resolve(raw, relativeTo: baseURL)
            else { return }
            let relation = attributes["rel"] ?? ""
            let type = attributes["type"] ?? ""
            let title = attributes["title"] ?? ""
            let count = Self.attribute("count", in: attributes).flatMap(Int.init)

            if entry != nil {
                entryLink(href: href, relation: relation, type: type)
                return
            }

            switch relation {
            case "next":
                next = href
            case "search":
                // Two shapes wear the same relation. Some servers put the query template
                // straight in the href; others point at an OpenSearch description document
                // that holds the template. Only the first is usable without another
                // request, so they are kept apart rather than guessed at.
                if raw.contains("{searchTerms}") {
                    searchTemplate = OpdsDocument.resolveTemplate(raw, relativeTo: baseURL)
                } else {
                    searchDescription = href
                }
            case "http://opds-spec.org/facet":
                facets.append(
                    OpdsFacet(
                        group: Self.attribute("facetGroup", in: attributes) ?? title,
                        title: title,
                        href: href,
                        count: count,
                        isActive: Self.attribute("activeFacet", in: attributes) == "true"
                    )
                )
            default:
                // A navigation link is one that points at another feed. The relation varies
                // — `subsection`, `start`, `sort_new`, or nothing at all — so the type is
                // what decides.
                guard type.contains("application/atom+xml"), !title.isEmpty else { return }
                guard !["self", "start", "up", "first", "last", "previous"].contains(relation)
                else { return }
                navigation.append(OpdsSection(title: title, href: href, count: count))
            }
        }

        private func entryLink(href: URL, relation: String, type: String) {
            switch relation {
            case "http://opds-spec.org/image", "http://opds-spec.org/cover":
                entry?.cover = href
            case "http://opds-spec.org/image/thumbnail", "http://opds-spec.org/thumbnail":
                entry?.thumbnail = href
            default:
                if let kind = OpdsAcquisition.Kind.named(relation) {
                    entry?.acquisitions.append(
                        OpdsAcquisition(href: href, mediaType: type, kind: kind)
                    )
                } else if relation.hasPrefix("http://opds-spec.org/acquisition") {
                    // A relation the standard added after this code was written. Listed as
                    // indirect rather than dropped: the spec requires an unsupported
                    // acquisition to be named, and a dropped link cannot be named.
                    entry?.acquisitions.append(
                        OpdsAcquisition(href: href, mediaType: type, kind: .indirect)
                    )
                }
            }
        }
    }

    /// An entry under construction.
    private struct PartialEntry {
        var id = ""
        var title = ""
        var authors: [String] = []
        var summary: String?
        var series: String?
        var updated: Date?
        var cover: URL?
        var thumbnail: URL?
        var acquisitions: [OpdsAcquisition] = []

        /// `nil` for an entry with no title, which is not something a reader can be shown.
        func finished() -> OpdsEntry? {
            guard !title.isEmpty else { return nil }
            return OpdsEntry(
                id: id.isEmpty ? title : id,
                title: title,
                authors: authors,
                summary: summary,
                series: series,
                updated: updated,
                cover: cover,
                thumbnail: thumbnail,
                acquisitions: acquisitions
            )
        }
    }
}

/// The date formats OPDS feeds actually use.
enum OpdsDates {
    /// RFC 3339, which Atom requires, and the date-only form several servers send anyway.
    ///
    /// A formatter per call rather than a shared one. `ISO8601DateFormatter` is not
    /// `Sendable`, and a feed is parsed once per request — the allocation is nothing beside
    /// the fetch that produced the bytes.
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }
}
