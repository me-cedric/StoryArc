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

    public init(kind: Kind, title: String, seriesId: Int = 0, downloadId: String? = nil) {
        self.kind = kind
        self.title = title
        self.seriesId = seriesId
        self.downloadId = downloadId
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
    /// The publication this describes, which is the identity the library computes for the
    /// downloaded file and therefore what the shelf looks the card up by.
    public let publicationId: String

    /// The download the file belongs to, which is a different key.
    ///
    /// `Download.id` is what the *source* calls the thing — for Kavita, the server's chapter.
    /// The publication's identity is the path the bytes ended up at. Both are needed and
    /// neither can be derived from the other, so the card holds both.
    public let downloadId: String

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
        downloadId: String = "",
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
        self.downloadId = downloadId
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

    /// Reads a card that was written by an older build of this app.
    ///
    /// **Written by hand because the synthesised one loses the whole cache.** A card is
    /// persisted, and Swift's derived `init(from:)` does not fall back to a property's
    /// default when the key is absent — it throws `keyNotFound`. ``KavitaCardStore`` decodes
    /// the cards as one dictionary with `try?`, so one card that a new field made
    /// undecodable does not degrade to five fields out of seven: it takes *every* card on the
    /// device with it, and the reader's whole offline library loses the server's word at
    /// once.
    ///
    /// So every field that has a default in the memberwise initialiser has the same default
    /// here, and only the four a card cannot mean anything without are required. Android
    /// gets this for free — a `@Serializable` property with a default is filled in when the
    /// key is missing — which is why the two platforms need different amounts of code to
    /// make the same promise.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationId = try container.decode(String.self, forKey: .publicationId)
        sourceId = try container.decode(String.self, forKey: .sourceId)
        seriesId = try container.decode(Int.self, forKey: .seriesId)
        chapterId = try container.decode(Int.self, forKey: .chapterId)
        downloadId = try container.decodeIfPresent(String.self, forKey: .downloadId) ?? ""
        libraryId = try container.decodeIfPresent(Int.self, forKey: .libraryId) ?? 0
        seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName) ?? ""
        chapterName = try container.decodeIfPresent(String.self, forKey: .chapterName) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        people = try container.decodeIfPresent([String].self, forKey: .people) ?? []
        subjects = try container.decodeIfPresent([String].self, forKey: .subjects) ?? []
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case publicationId, downloadId, sourceId, libraryId, seriesId, chapterId
        case seriesName, chapterName, summary, people, subjects, releaseYear
    }

    /// Everything a one-line summary row shows, already in order.
    ///
    /// The same line `KavitaMetadata.facts` builds from a live answer, so a series read
    /// offline reads the way it did online rather than losing its shape with its server.
    public var facts: [String] {
        (releaseYear > 0 ? [String(releaseYear)] : []) + people + subjects
    }

    /// This publication as the server describes it, rather than as its file does.
    ///
    /// **Both of `kavita-server`'s metadata scenarios are this one function.** "When a
    /// publication's `ComicInfo.xml` disagrees with Kavita's metadata, the app displays
    /// Kavita's values, because the server is the curated source"; and "when a downloaded
    /// Kavita publication is opened with the server unreachable, the cached server metadata
    /// is displayed, not the file's embedded metadata". The second is the first, applied
    /// from disk instead of from a live answer — which is the whole reason the card is
    /// written down when the download is taken.
    ///
    /// The result is ``MetadataOrigin/authoritative``, so nothing downstream silently puts
    /// the file's values back: that ordering already exists and this is what it was for.
    ///
    /// A field the card is silent about keeps what the file said. The server not having a
    /// summary is not the server saying there is none, and blanking a description the file
    /// does have would be losing information in the name of preferring a source.
    public func applied(to publication: Publication) -> Publication {
        Publication(
            identity: publication.identity,
            format: publication.format,
            displayTitle: chapterName.isEmpty ? publication.displayTitle : chapterName,
            series: seriesName.isEmpty ? publication.series : seriesName,
            number: publication.number,
            volume: publication.volume,
            authors: people.isEmpty ? publication.authors : people,
            publisher: publication.publisher,
            year: releaseYear > 0 ? releaseYear : publication.year,
            language: publication.language,
            summary: summary?.isEmpty == false ? summary : publication.summary,
            genres: publication.genres,
            tags: subjects.isEmpty ? publication.tags : subjects,
            origin: .authoritative,
            pageCount: publication.pageCount,
            skippedPageCount: publication.skippedPageCount,
            coverPath: publication.coverPath,
            readingDirection: publication.readingDirection,
            isFixedLayout: publication.isFixedLayout,
            streaming: publication.streaming,
            sourceID: publication.sourceID,
            fileSize: publication.fileSize,
            modifiedAt: publication.modifiedAt,
            addedAt: publication.addedAt
        )
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
                title: card.chapterName,
                seriesId: card.seriesId,
                downloadId: card.downloadId
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
