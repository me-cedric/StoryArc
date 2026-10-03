public import Foundation

/// One thing a search of a Kavita server matched.
///
/// `kavita-server` asks a server-side search for "matches across series, chapters, people,
/// genres, and tags — not only titles cached locally". A genre and a tag are the same kind
/// of thing to a reader, so they arrive as one kind here, for the reason
/// ``KavitaCard/subjects`` gives.
/// The two numbers Kavita writes when it means "this has no number", as it writes them
/// into a name.
///
/// Quoted from `Kavita.Models/Constants/ParserConstants.cs`:
/// `public const string LooseLeafVolume = "-100000";` and
/// `public const string SpecialVolume = "100000";`
///
/// Kavita derives a chapter's title and a volume's name from the number, so both sentinels
/// reach this app as text as well as as integers. Here, in the module underneath, because a
/// card read from disk needs the same answer as a chapter read from the wire — and the whole
/// defect was four places asking the question separately and disagreeing. Android's
/// `SENTINEL_NAMES` is the twin.
public let kavitaSentinelNames: Set<String> = ["-100000", "100000"]

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

    /// The download on this device this row opens, when the row came from the cache.
    ///
    /// Nil for everything the server answered: the server knows about publications this
    /// device has never held. Set for a cached row, which is the difference that matters —
    /// with the server away, a row that cannot be opened is a row that is only there to
    /// disappoint.
    ///
    /// The *download's* identifier, not the publication's. They are two different keys and
    /// driving this proved it: a download is filed under what the server calls the chapter,
    /// and the publication under the path the file ended up at.
    public let downloadId: String?

    /// Which chapter this row is, when the row is a chapter.
    ///
    /// Part of ``id`` and nothing else. Two chapters of one series can carry the same words
    /// — both untitled, both unnumbered — and without this they were one key, which a keyed
    /// list refuses.
    public let chapterId: Int

    public init(
        kind: Kind,
        title: String,
        seriesId: Int = 0,
        downloadId: String? = nil,
        chapterId: Int = 0
    ) {
        self.kind = kind
        self.title = title
        self.seriesId = seriesId
        self.downloadId = downloadId
        self.chapterId = chapterId
    }

    /// Identity is what the row *is*, not where it came from: the same series found twice —
    /// once by its own name, once through a chapter — is one row, and a list keyed on
    /// anything finer would draw it twice.
    public var id: String { "\(kind):\(seriesId):\(chapterId):\(title)" }

    /// Whether opening this row leads anywhere.
    public var isOpenable: Bool { seriesId > 0 }
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

        // A series row opens the first chapter of it this device holds. Offline there is
        // nothing else it could open — the series itself lives on a server that is not
        // answering, and the reader asked for something they can read now.
        for card in cards where matches(card.seriesName) {
            add(KavitaHit(
                kind: .series,
                title: card.seriesName,
                seriesId: card.seriesId,
                downloadId: card.downloadId
            ))
        }
        for card in cards where matches(card.chapterName) {
            add(KavitaHit(
                kind: .chapter,
                title: card.properChapterName ?? "",
                seriesId: card.seriesId,
                downloadId: card.downloadId,
                chapterId: card.chapterId
            ))
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
