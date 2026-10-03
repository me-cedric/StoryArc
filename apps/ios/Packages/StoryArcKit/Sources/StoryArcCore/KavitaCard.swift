internal import Foundation

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
///
/// Split out of `KavitaFind.swift`, which carried `KavitaHit`, this struct and the search
/// itself and crossed the 400-line cap the moment D36 gave the card a status to carry. The
/// seam is the one the file already had: `KavitaHit` and `KavitaFind` are about searching a
/// server, and this is about remembering what one said.
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

    /// Kavita's own `ageRating` number, so the rating outlives the server.
    ///
    /// The number rather than a name, because `StoryArcCore` is where a card lives and the
    /// table that reads it is Kavita's: `KavitaAgeRating` in the `Kavita` module turns this
    /// into a label, and `KavitaCard.rating` applies the same two rules the live answer gets.
    ///
    /// Zero is Kavita's own `Unknown`, which is not a rating and draws no line — so it is
    /// both the right default for a card written before this field existed and the right
    /// value for a keep whose server had no metadata to give.
    public let ageRating: Int

    /// Kavita's own `publicationStatus` number, or -1 for a card that never recorded one.
    ///
    /// **The sentinel is the point.** Kavita's own range is 0 to 4 and *zero means OnGoing* —
    /// a real state a curator chose, not an absence. A card written before this field existed
    /// would decode zero and the screen would state that the series is running, which the
    /// server may never have said. -1 is outside Kavita's table, so `KavitaPublicationStatus`
    /// reads it as a number it has never heard of and the line is left unsaid.
    public let publicationStatus: Int

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
        releaseYear: Int = 0,
        ageRating: Int = 0,
        publicationStatus: Int = -1
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
        self.ageRating = ageRating
        self.publicationStatus = publicationStatus
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
    /// So the four a card cannot be looked up or attributed without are required —
    /// `publicationId`, `sourceId`, `seriesId`, `chapterId` — and every other key, including
    /// the two names the memberwise initialiser above does require of a caller, falls back
    /// rather than throwing. The two differ on purpose: code building a card has the names
    /// and should say them; bytes already on disk are not code, and refusing them would
    /// empty the cache.
    ///
    /// Android reaches the same tolerance through kotlinx.serialization — a `@Serializable`
    /// property with a default is filled in when the key is missing — which is why
    /// Android's `KavitaCard` gives `seriesName` and `chapterName` defaults it does not
    /// otherwise need.
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
        ageRating = try container.decodeIfPresent(Int.self, forKey: .ageRating) ?? 0
        publicationStatus = try container
            .decodeIfPresent(Int.self, forKey: .publicationStatus) ?? -1
    }

    private enum CodingKeys: String, CodingKey {
        case publicationId, downloadId, sourceId, libraryId, seriesId, chapterId
        case seriesName, chapterName, summary, people, subjects, releaseYear
        case ageRating, publicationStatus
    }

    /// Everything a one-line summary row shows, already in order.
    ///
    /// The same line `KavitaMetadata.facts` builds from a live answer, so a series read
    /// offline reads the way it did online rather than losing its shape with its server.
    public var facts: [String] {
        (releaseYear > 0 ? [String(releaseYear)] : []) + people + subjects
    }

    /// The row this download is a copy of, as the library's own identifier for it.
    ///
    /// `library-browsing`: a publication a source offers and the same publication
    /// downloaded are one row. They were two, and the reason was spelling — a server row is
    /// identified by `ServerIdentifier(sourceID, "chapter:<id>")` and a downloaded file by
    /// its path and its digest, so `PublicationIdentity.matches` had nothing in common to
    /// match on. The card bridges them because it is written when the chapter is kept and
    /// holds both the source and the chapter.
    ///
    /// The spelling has to be the one ``KavitaContributor`` uses; `DownloadFoldTests` is
    /// what holds the two together. `nil` when the card's source is not a UUID, which is a
    /// card written by something that was not this app.
    public var remoteIdentity: PublicationIdentity.ServerIdentifier? {
        guard let source = UUID(uuidString: sourceId) else { return nil }
        return PublicationIdentity.ServerIdentifier(sourceID: source, remoteID: "chapter:\(chapterId)")
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
    /// The chapter's name, or nil where what was written down was a sentinel.
    ///
    /// **Read-time rather than a migration.** A card is written once, at the moment a
    /// chapter is kept, and nothing rewrites it. Cards kept before the guard existed hold
    /// "-100000" as the chapter's name, and that string wins over the file's own title
    /// because a card is `authoritative`. Checking here repairs every such card the first
    /// time it is read, on a device nobody can reach to migrate.
    public var properChapterName: String? {
        let trimmed = chapterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !kavitaSentinelNames.contains(trimmed) else { return nil }
        return chapterName
    }

    /// The status this card kept, as the library's own ``PublicationStatus`` rather than
    /// Kavita's, or `nil` when it kept none.
    ///
    /// Named apart from the `Kavita` module's own `KavitaCard.status` extension (which this
    /// exact file's ``publicationStatus`` already backs): the two modules are both visible
    /// wherever a card is read, and reusing the name made `card.status` ambiguous rather
    /// than wrong in a way a type mismatch would have caught.
    ///
    /// `nil` covers two things and has to: a number Kavita has never defined, and the -1
    /// ``publicationStatus`` carries for a card written before the field existed —
    /// ``PublicationStatus/init(kavita:)`` holds the table.
    public var libraryStatus: PublicationStatus? {
        PublicationStatus(kavita: publicationStatus)
    }

    public func applied(to publication: Publication) -> Publication {
        Publication(
            identity: publication.identity,
            format: publication.format,
            displayTitle: properChapterName ?? publication.displayTitle,
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
            // The server's own status wins; a card that stated none leaves whatever the
            // publication already carried — which may be a status the reader set by hand,
            // and D36 forbids a report from being the only thing allowed to clear that.
            status: libraryStatus ?? publication.status,
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
