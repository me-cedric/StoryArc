public import Foundation

/// One thing a search of a Kavita server matched.
///
/// `kavita-server` asks a server-side search for "matches across series, chapters, people,
/// genres, and tags — not only titles cached locally". A genre and a tag are the same kind
/// of thing to a reader, so they arrive as one kind here, for the reason
/// ``KavitaCard/subjects`` gives.
public struct KavitaHit: Sendable, Equatable, Hashable, Identifiable {
    /// Which of the spec's five a match is, and therefore which heading it appears under.
    public enum Kind: Sendable, Equatable, Hashable, CaseIterable {
        case series
        case chapter
        case person

        /// A genre or a tag. Kavita keeps them apart; a reader looking for "horror" does not.
        case subject
    }

    public let kind: Kind
    public let title: String

    /// The series this leads to, or zero when it leads nowhere.
    ///
    /// A person and a subject are names the server matched, not places: Kavita answers with
    /// the name alone, and a row that looked tappable and did nothing would be worse than a
    /// row that plainly is not.
    public let seriesId: Int

    public init(kind: Kind, title: String, seriesId: Int = 0) {
        self.kind = kind
        self.title = title
        self.seriesId = seriesId
    }

    /// Identity is what the row *is*, not where it came from: the same series found twice —
    /// once by its own name, once through a chapter — is one row, and a list keyed on
    /// anything finer would draw it twice.
    public var id: String { "\(kind):\(seriesId):\(title)" }

    /// Whether opening this row leads anywhere.
    public var isOpenable: Bool { seriesId > 0 }
}

/// What a server said about a publication, kept so it can be read without the server.
///
/// `kavita-server`: "when a downloaded Kavita publication is opened with the server
/// unreachable, the cached server metadata is displayed, not the file's embedded metadata".
/// The file has its own `ComicInfo.xml` and the spec is explicit that the server wins, so
/// what the server said has to survive the server going away — which means being written
/// down when the download is taken, not fetched when the reader arrives.
///
/// A value with no network and no disk in it. `Persistence`'s `KavitaCardStore` writes it;
/// Android's `KavitaCard` mirrors it field for field.
public struct KavitaCard: Sendable, Equatable, Codable, Identifiable {
    /// The publication this describes, which is what a reader opens and what the store keys on.
    public let publicationId: String

    /// Which source it came from, so removing a server can take its cards with it.
    public let sourceId: String

    /// The whole chain Kavita keys its own rows by, not the chapter alone.
    ///
    /// `KavitaOrigin` carries the same four for the same reason: a progress post missing one
    /// of them is refused, and a card that could not rebuild the origin would be a download
    /// that reads offline and never reports what was read.
    public let libraryId: Int

    public let seriesId: Int
    public let chapterId: Int
    public let seriesName: String
    public let chapterName: String

    public let summary: String?
    public let people: [String]

    /// Genres and tags read as one list; the distinction is Kavita's, not the reader's.
    public let subjects: [String]

    public let releaseYear: Int

    public var id: String { publicationId }

    public init(
        publicationId: String,
        sourceId: String,
        libraryId: Int = 0,
        seriesId: Int,
        chapterId: Int,
        seriesName: String,
        chapterName: String,
        summary: String? = nil,
        people: [String] = [],
        subjects: [String] = [],
        releaseYear: Int = 0
    ) {
        self.publicationId = publicationId
        self.sourceId = sourceId
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.chapterId = chapterId
        self.seriesName = seriesName
        self.chapterName = chapterName
        self.summary = summary
        self.people = people
        self.subjects = subjects
        self.releaseYear = releaseYear
    }

    /// Everything a one-line summary row shows, already in order.
    ///
    /// The same line `KavitaMetadata.facts` builds from a live answer, so a series read
    /// offline reads the way it did online rather than losing its shape with its server.
    public var facts: [String] {
        (releaseYear > 0 ? [String(releaseYear)] : []) + people + subjects
    }
}

/// Searching a Kavita source, and what a search falls back to when the server is away.
///
/// Pure, and deliberately so: `kavita-server` has two search scenarios and the difference
/// between them is a decision, not a screen. Android's `KavitaFind` mirrors it, asserted
/// against the same table in the same order.
public enum KavitaFind {
    /// The term a query actually asks for, or `nil` when it asks for nothing.
    ///
    /// Whitespace alone is nothing. A server asked for it answers with its whole library,
    /// which reads as a search that matched everything.
    public static func term(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What a term matches in what this device already holds.
    ///
    /// `kavita-server`: with the server unreachable "the search falls back to the local
    /// cache and states that results are limited to cached content". The cache is the cards
    /// kept beside downloads — the only Kavita metadata that is ever written to disk, for
    /// the reason `sources` gives for not writing the rest of a server's answers down.
    ///
    /// The order is the spec's own — series, chapters, people, genres and tags — rather
    /// than a ranking. A reader who cannot reach their server is looking for a particular
    /// book they already have, and the shape of the answer should not change with the
    /// server's mood.
    public static func inCache(_ term: String, _ cards: [KavitaCard]) -> [KavitaHit] {
        guard let needle = self.term(term)?.lowercased() else { return [] }

        var hits: [KavitaHit] = []
        var seen: Set<String> = []

        func add(_ hit: KavitaHit) {
            guard seen.insert(hit.id).inserted else { return }
            hits.append(hit)
        }

        func matches(_ text: String) -> Bool { text.lowercased().contains(needle) }

        for card in cards where matches(card.seriesName) {
            add(KavitaHit(kind: .series, title: card.seriesName, seriesId: card.seriesId))
        }
        for card in cards where matches(card.chapterName) {
            add(KavitaHit(kind: .chapter, title: card.chapterName, seriesId: card.seriesId))
        }
        for card in cards {
            for person in card.people where matches(person) {
                add(KavitaHit(kind: .person, title: person))
            }
        }
        for card in cards {
            for subject in card.subjects where matches(subject) {
                add(KavitaHit(kind: .subject, title: subject))
            }
        }
        return hits
    }

    /// One search's hits under their headings, in the spec's own order.
    ///
    /// A kind that matched nothing is left out rather than drawn as a heading over nothing,
    /// which is the rule `library-browsing` applies to its own group headings.
    public static func grouped(_ hits: [KavitaHit]) -> [(kind: KavitaHit.Kind, hits: [KavitaHit])] {
        KavitaHit.Kind.allCases.compactMap { kind in
            let inKind = hits.filter { $0.kind == kind }
            return inKind.isEmpty ? nil : (kind, inKind)
        }
    }
}
