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

        /// An entry-level link not yet resolved to an acquisition, because OPDS lets a
        /// `<link>` carry an `<opds:indirectAcquisition>` child that only its end tag has
        /// finished naming — see 11.4's `finalizePendingAcquisition()`.
        private var pendingAcquisition: (href: URL, relation: String, type: String, length: Int64?)?
        private var pendingAcquisitionIsIndirect = false

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
            case "indirectAcquisition":
                // 11.4: its mere presence means another step stands between this link and
                // an openable file — OPDS-LCP chief among them — whatever format the step
                // ends in. The type it carries is not read: the outer link's own type is
                // what `publication-formats` already shows the reader as "offered as".
                if pendingAcquisition != nil { pendingAcquisitionIsIndirect = true }
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
                if let current = entry, let finished = current.finished() {
                    // OPDS 1.2 puts each section of a navigation feed in its own `entry`,
                    // carrying one `application/atom+xml` link rather than an acquisition.
                    // An entry with nothing to acquire and such a link is that section, not
                    // a publication with no download — 11.1.
                    if finished.acquisitions.isEmpty, let section = current.asSection() {
                        navigation.append(section)
                    } else {
                        publications.append(finished)
                    }
                }
                entry = nil
                return
            }
            if element == "link", entry != nil {
                finalizePendingAcquisition()
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
                // 11.1: the one link an OPDS 1.2 section entry carries, not an acquisition
                // and not the entry's own permalink.
                if type.contains("application/atom+xml"), !["self", "up", "start"].contains(relation) {
                    entry?.sectionLink = (href, count)
                }
                // RFC 4287's own attribute, unprefixed, and advisory by its own definition.
                entryLink(
                    href: href,
                    relation: relation,
                    type: type,
                    length: attributes["length"].flatMap(Int64.init)
                )
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

        private func entryLink(href: URL, relation: String, type: String, length: Int64?) {
            switch relation {
            case "http://opds-spec.org/image", "http://opds-spec.org/cover":
                entry?.cover = href
            case "http://opds-spec.org/image/thumbnail", "http://opds-spec.org/thumbnail":
                entry?.thumbnail = href
            default:
                // Not appended yet: `didEndElement("link")` finishes this once it knows
                // whether an `indirectAcquisition` child followed — see
                // `finalizePendingAcquisition()`.
                pendingAcquisition = (href, relation, type, length)
                pendingAcquisitionIsIndirect = Self.isProtectedType(type)
            }
        }

        /// Turns the link `entryLink` deferred into an acquisition, now that its end tag
        /// has been seen and an `indirectAcquisition` child — if any — has already set
        /// ``pendingAcquisitionIsIndirect``. 11.4.
        private func finalizePendingAcquisition() {
            guard let pending = pendingAcquisition else { return }
            defer {
                pendingAcquisition = nil
                pendingAcquisitionIsIndirect = false
            }
            if pendingAcquisitionIsIndirect {
                entry?.acquisitions.append(
                    OpdsAcquisition(href: pending.href, mediaType: pending.type, kind: .indirect, length: pending.length)
                )
            } else if let kind = OpdsAcquisition.Kind.named(pending.relation) {
                entry?.acquisitions.append(
                    OpdsAcquisition(href: pending.href, mediaType: pending.type, kind: kind, length: pending.length)
                )
            } else if pending.relation.hasPrefix("http://opds-spec.org/acquisition") {
                // A relation the standard added after this code was written. Listed as
                // indirect rather than dropped: the spec requires an unsupported
                // acquisition to be named, and a dropped link cannot be named.
                entry?.acquisitions.append(
                    OpdsAcquisition(href: pending.href, mediaType: pending.type, kind: .indirect, length: pending.length)
                )
            }
        }

        /// A media type that names a protection step rather than an openable file —
        /// OPDS-LCP's license, or Adobe's ADEPT activation. 11.4: without this, a link
        /// typed to one of these parsed as `direct` and the refusal named the wrapper's
        /// media type instead of saying the acquisition itself is unsupported.
        private static func isProtectedType(_ type: String) -> Bool {
            type == "application/vnd.adobe.adept+xml"
                || type.contains("vnd.readium.lcp.license")
                || type.hasSuffix("+lcp")
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

        /// The entry's `application/atom+xml` link, when it has exactly the shape an OPDS
        /// 1.2 section entry does. See ``asSection()``.
        var sectionLink: (href: URL, count: Int?)?

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

        /// This entry, read as an OPDS 1.2 navigation section instead of a publication.
        ///
        /// `nil` unless the entry carried no acquisition and did carry the one link that
        /// makes it a section — never both, because a publication already answers
        /// ``finished()`` and a plain entry answers neither.
        func asSection() -> OpdsSection? {
            guard !title.isEmpty, let link = sectionLink else { return nil }
            return OpdsSection(title: title, href: link.href, count: link.count)
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
