public import Foundation

/// One page of an OPDS catalogue, in the shape the app browses.
///
/// `opds-catalog` requires the app to "support OPDS 1.2 (Atom) and OPDS 2.0 (JSON),
/// detecting the version from the response". Two wire formats, one model: the browsing
/// code should not know which one it came from, or a facet would have to be implemented
/// twice and would drift.
public struct OpdsFeed: Sendable, Equatable {
    /// Shown as confirmation when a catalogue is added, per the spec's first scenario.
    public let title: String

    /// Sections a reader can enter. Empty for a pure acquisition feed.
    public let navigation: [OpdsSection]

    /// Publications on this page. Empty for a pure navigation feed.
    public let publications: [OpdsEntry]

    /// The named runs an OPDS 2.0 feed divides itself into. Empty for OPDS 1.2, which has
    /// no such thing, and for a 2.0 feed that declares none.
    public let groups: [OpdsGroup]

    /// Filters the server offers, surfaced through `library-browsing`'s controls.
    public let facets: [OpdsFacet]

    /// The next page, followed as the reader scrolls. `opds-catalog` forbids a visible
    /// "load more", so this is read by the scroll rather than by a button.
    public let next: URL?

    /// Where a search goes when the catalogue advertises one.
    ///
    /// A template, not a URL: OpenSearch gives `…?q={searchTerms}` and OPDS 2.0 gives an
    /// href with the same braces. Substitution happens at the moment of searching, so the
    /// unresolved form is what is stored.
    public let searchTemplate: String?

    /// Where a template lives, when the feed pointed at an OpenSearch description document
    /// instead of carrying the template itself. One more request, and only when a reader
    /// actually searches.
    public let searchDescription: URL?

    public init(
        title: String,
        navigation: [OpdsSection] = [],
        publications: [OpdsEntry] = [],
        groups: [OpdsGroup] = [],
        facets: [OpdsFacet] = [],
        next: URL? = nil,
        searchTemplate: String? = nil,
        searchDescription: URL? = nil
    ) {
        self.title = title
        self.navigation = navigation
        self.publications = publications
        self.groups = groups
        self.facets = facets
        self.next = next
        self.searchTemplate = searchTemplate
        self.searchDescription = searchDescription
    }

    /// Whether this page holds publications rather than sections.
    ///
    /// A feed can hold both, and several real servers do — Calibre-Web puts "Recently
    /// added" beside its sections. So this asks what to *show first*, not what the feed is.
    public var isAcquisition: Bool {
        !publications.isEmpty || groups.contains { !$0.publications.isEmpty }
    }

    /// Whether there is nothing on this page at all.
    ///
    /// Asked by the browser before it says a section is empty, and it has to count the
    /// groups: a 2.0 feed that puts everything in groups has no top-level anything, and
    /// calling that empty told readers their catalogue was.
    public var isEmpty: Bool { navigation.isEmpty && publications.isEmpty && groups.isEmpty }
}

/// A named run of a catalogue, as an OPDS 2.0 feed declares it.
///
/// `opds-catalog` browses what the feed says, and a 2.0 feed says "New this week" and
/// "Continue reading" are two things rather than one. They used to be poured into a single
/// list, which lost both names — the reader saw one undivided run of covers, and a server
/// that had carefully arranged its front page might as well not have bothered.
///
/// A group holds the same three things a feed does, because in the standard it is a feed:
/// the shape recurses, and the browser renders the group with the same views it renders the
/// page with.
public struct OpdsGroup: Sendable, Equatable {
    /// What the group is called. A group without one is not a group anybody can label, so
    /// the parser folds its contents into the feed instead of showing an unnamed section.
    public let title: String

    /// Sections inside the group.
    public let navigation: [OpdsSection]

    /// Publications inside the group.
    public let publications: [OpdsEntry]

    /// The whole of this group, as its own page.
    ///
    /// A group is a *sample* — a server sends the first handful of "Recently added" and a
    /// `self` link to the rest. Nil where the feed offers no such link, and then the group
    /// is all there is and there is nothing to open.
    public let more: URL?

    public init(
        title: String,
        navigation: [OpdsSection] = [],
        publications: [OpdsEntry] = [],
        more: URL? = nil
    ) {
        self.title = title
        self.navigation = navigation
        self.publications = publications
        self.more = more
    }
}

/// A section of a catalogue, which is a link to another feed.
public struct OpdsSection: Sendable, Equatable, Identifiable {
    public var id: URL { href }

    public let title: String
    public let href: URL

    /// How many publications the section holds, when the feed says.
    ///
    /// `opds-catalog`: each section is shown "with its title and, where the feed provides
    /// one, its item count". Optional because most servers do not provide one, and a
    /// fabricated zero would read as an empty section.
    public let count: Int?

    public init(title: String, href: URL, count: Int? = nil) {
        self.title = title
        self.href = href
        self.count = count
    }
}

/// A filter the server offers.
public struct OpdsFacet: Sendable, Equatable, Identifiable {
    public var id: URL { href }

    /// The group this facet belongs to — "Language", "Sort by". Facets in one group are
    /// alternatives to each other, which is what makes them a filter rather than a list.
    public let group: String
    public let title: String
    public let href: URL
    public let count: Int?

    /// Whether the server says this facet is the one currently applied.
    public let isActive: Bool

    public init(group: String, title: String, href: URL, count: Int? = nil, isActive: Bool = false) {
        self.group = group
        self.title = title
        self.href = href
        self.count = count
        self.isActive = isActive
    }
}

/// One publication in a catalogue, before it is downloaded.
///
/// Deliberately not a ``Publication``: that type describes a file this device can open,
/// and this describes something on a server that may not be readable at all. Conflating
/// them is how a library ends up listing a title it cannot open.
public struct OpdsEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let summary: String?
    public let series: String?
    public let seriesIndex: Double?
    public let updated: Date?

    /// Cover art, at whatever size the server offered.
    public let cover: URL?
    public let thumbnail: URL?

    /// Every way this entry can be obtained, in the order the feed listed them.
    public let acquisitions: [OpdsAcquisition]

    public init(
        id: String,
        title: String,
        authors: [String] = [],
        summary: String? = nil,
        series: String? = nil,
        seriesIndex: Double? = nil,
        updated: Date? = nil,
        cover: URL? = nil,
        thumbnail: URL? = nil,
        acquisitions: [OpdsAcquisition] = []
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.summary = summary
        self.series = series
        self.seriesIndex = seriesIndex
        self.updated = updated
        self.cover = cover
        self.thumbnail = thumbnail
        self.acquisitions = acquisitions
    }
}

/// One way to obtain a publication.
public struct OpdsAcquisition: Sendable, Equatable {
    public let href: URL

    /// The media type the feed declared, verbatim. Kept as written rather than mapped to
    /// a ``PublicationFormat`` here: the spec requires an unreadable entry to name "the
    /// formats offered", and a type that mapped to nothing would have no name to give.
    public let mediaType: String

    public let kind: Kind

    /// How many bytes the feed says this is, when it says.
    ///
    /// `offline-downloads` requires a queued download to show "its size", and a collection
    /// to state "the item count and total size" *before* anything is fetched — which is
    /// only possible from a number the catalogue sent. OPDS 1.2 spells it as the Atom
    /// link's `length` attribute and OPDS 2.0 as the Readium Link Object's `size`; both
    /// mean the same octets, so they arrive here as one field.
    ///
    /// **Advisory, and never used to allocate.** RFC 4287 calls `length` a hint, and a
    /// catalogue is untrusted input like any other file: the authority on how many bytes a
    /// publication has is the transfer itself. ADR-0008's rule — no length field out of a
    /// file decides a buffer — applies to a feed exactly as it applies to a ZIP header.
    /// This number is for telling a reader what they are about to spend, and for nothing
    /// else.
    public let length: Int64?

    public init(href: URL, mediaType: String, kind: Kind, length: Int64? = nil) {
        self.href = href
        self.mediaType = mediaType
        self.kind = kind
        // A zero or a negative is a server filling in a field it does not know the answer
        // to. Kept as "no size stated" rather than shown as a 0 KB download.
        self.length = length.flatMap { $0 > 0 ? $0 : nil }
    }

    /// What obtaining it involves.
    ///
    /// `opds-catalog` requires an unsupported acquisition to be *stated* rather than to
    /// fail silently, so every relation the standard defines is named here — including the
    /// ones the app will refuse.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// A direct download, free to take.
        case open

        /// A direct download the reader has already paid for or is entitled to.
        case direct

        /// A loan. Requires a flow StoryArc does not implement.
        case borrow

        /// A purchase. Requires a payment flow StoryArc does not implement.
        case buy

        /// A subscription.
        case subscribe

        /// An excerpt.
        case sample

        /// Something reached through another acquisition step, such as OPDS-LCP.
        case indirect

        /// Whether the app can act on it. Only a direct link is something to fetch.
        public var isFetchable: Bool { self == .open || self == .direct || self == .sample }

        /// The Atom relation this corresponds to, for parsing and for tests.
        public static func named(_ relation: String) -> Kind? {
            switch relation {
            case "http://opds-spec.org/acquisition",
                 "http://opds-spec.org/acquisition/open-access":
                relation.hasSuffix("open-access") ? .open : .direct
            case "http://opds-spec.org/acquisition/borrow": .borrow
            case "http://opds-spec.org/acquisition/buy": .buy
            case "http://opds-spec.org/acquisition/subscribe": .subscribe
            case "http://opds-spec.org/acquisition/sample": .sample
            default: nil
            }
        }
    }
}
