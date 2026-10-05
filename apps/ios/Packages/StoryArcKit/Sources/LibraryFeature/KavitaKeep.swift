internal import Foundation

internal import Catalogue
internal import Formats
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Keeping a Kavita chapter on the device, as a download rather than as a cache file.
///
/// **This is what "a downloaded Kavita publication" was missing.** `kavita-server` has a
/// scenario about opening one "with the server unreachable", and the subject of that
/// sentence did not exist: every chapter the browser fetched went to the caches directory,
/// which nothing lists, nothing attributes to a source, nothing counts in Settings ›
/// Downloads and storage, and the system may reclaim between two launches. The comment that
/// sent it there was right about the distinction — "a chapter opened once is not a download
/// the reader asked to keep" — and wrong that there was no way to ask.
///
/// So opening still writes a cache file, and *keeping* writes a download: the same
/// ``DownloadStore`` every other kept publication goes through, with the same record, the
/// same per-source attribution, the same removal, and the same hardened naming. That store
/// was hardened this session against an id made of dots; a second path that wrote files
/// beside it would be a second path to harden.
///
/// The card goes with it. A download whose metadata is fetched on arrival is a download that
/// has no metadata when the server is away, which is the scenario.
///
/// Android's `KavitaKeep` does the same four steps in the same order.
enum KavitaKeep {
    /// What a keep produced, for the caller that wants to open it straight away.
    struct Kept {
        let publication: Publication
        let file: URL
    }

    /// What is being kept: the chapter, and everything the record has to name.
    ///
    /// One value rather than five parameters. They are not five decisions — they are one
    /// chapter described from five angles, and the screen that has one has all of them.
    struct Subject {
        let chapter: KavitaChapter
        let series: KavitaSeries

        /// What the server said about the series, when it was asked and answered. Nil is a
        /// card with a name and no description, which is better than no card.
        let metadata: KavitaMetadata?

        let origin: KavitaOrigin

        /// The registry's identifier for the server, which is what attributes the download.
        let sourceID: UUID?
    }

    /// Queues a chapter, waits for its file, and writes down what the server said.
    ///
    /// Nil when any step fails, and deliberately without a half-kept result: a record whose
    /// bytes are not there reads to a reader as a library that lost their book, which is the
    /// failure ``DownloadStore`` exists to make impossible.
    ///
    /// **The transfer is the queue's, not this type's.** `offline-downloads` 1.9: the body
    /// used to be fetched whole into a `Data`, written to a cache file and moved into the
    /// store by hand, so a kept chapter had no row in the downloads view and none of the
    /// pause, resume or retry *Queue management* promises — and a collected edition was a
    /// buffer the size of itself. ``DownloadQueue/fetchChapter(id:title:from:sourceID:credential:seriesHint:)``
    /// streams it to disk instead, and the token travels with the chapter because the secure
    /// store holds the API key that mints one rather than the token this route needs.
    ///
    /// The four steps afterwards are unchanged: index the landed file, attribute it, file the
    /// card, and remember where the chapter sits on the server.
    @MainActor
    static func keep(
        _ subject: Subject,
        client: KavitaClient,
        cards: KavitaCardStore = KavitaCardStore(),
        progress: KavitaProgressStore,
        queue: DownloadQueue = .shared()
    ) async -> Kept? {
        let (chapter, series, origin, sourceID) =
            (subject.chapter, subject.series, subject.origin, subject.sourceID)

        // The same name the shelf gives it. The raw `displayName` was the bug: empty for
        // an unnumbered chapter, and the fallback spelled the sentinel straight into the
        // file's name, so a kept collected edition landed on disk as "-100000.cbz".
        let title = KavitaContributor.title(of: chapter, in: series)

        // The record's own identifier, and therefore the directory the bytes go in.
        //
        // The server's chapter, not the file's identity. It was the file's, and driving it
        // showed why that cannot work: the identity of a publication is its path, the path
        // is chosen from the identity, and the file the reader ends up with is at a *third*
        // path — so the card was filed under the staging directory and the shelf, indexing
        // the download, never found it. A catalogue download has the same shape and solved
        // it the same way: `Download.id` is what the *source* calls the thing.
        let identifier = "kavita:\(origin.sourceId):\(chapter.id)"

        // No secret in it: Kavita takes the key as a bearer header on this route, not in the
        // query, so what is written down is a path and a chapter number.
        guard let remote = await client.address.chapterURL(chapter.id),
              let token = try? await client.authorization(),
              let destination = await queue.fetchChapter(
                  id: identifier,
                  title: title,
                  from: remote,
                  sourceID: sourceID,
                  credential: .bearer(token: token),
                  seriesHint: series.name
              )
        else { return nil }

        // Indexed where it landed, which is the identity the library will compute when it
        // walks the download tree — and what the card has to be filed under for the server's
        // metadata to reach the shelf.
        guard var publication = try? await PublicationIndexer.index(
            fileAt: destination,
            catalogueSeries: series.name
        ) else { return nil }
        // `library-browsing` attributes a download to the source its record names, which is
        // what puts a kept chapter on the one shelf that spans every source.
        publication.sourceID = sourceID

        cards.save(card(publication.id, downloadId: identifier, subject))
        // The same note the open path leaves, and for the same reason: the reader opens a
        // file and knows nothing about servers, so this is what lets the position get home.
        progress.remember(origin, for: publication.id)

        return Kept(publication: publication, file: destination)
    }

    /// What the server said, in the shape that survives it going away.
    ///
    /// **All seven of `kavita-server`'s metadata fields** — "summary, genres, tags, people,
    /// publication status, age rating, and release year". The last two were the gap:
    /// `KavitaCard` had no field for either, so *Reading a downloaded Kavita title offline*
    /// fell back to the file's `ComicInfo.xml` for exactly those two while preferring the
    /// server's word for the rest.
    ///
    /// The two defaults are not the same shape, and that is deliberate. A rating the server
    /// did not state is Kavita's own `Unknown`, which is zero and draws no line. A *status*
    /// it did not state has no number of its own — zero is `OnGoing`, a real state — so the
    /// card carries -1, outside Kavita's table, rather than telling a reader a series is
    /// running on a server's behalf.
    ///
    /// Both absences reach the -1, and that is why ``KavitaMetadata/publicationStatus`` is
    /// optional: the server not answering at all, and the server answering without the
    /// field. The second is the ordinary one — Kavita omits what a series does not have —
    /// and a non-optional field defaulted to zero would have turned it into *OnGoing* here.
    ///
    /// Internal rather than private because these two lines are the whole feature: hardcode
    /// them to the two absences and every screen in the app still composes.
    /// ``KavitaKeepCardTests`` is the test that fails.
    static func card(
        _ publicationId: String,
        downloadId: String,
        _ subject: Subject
    ) -> KavitaCard {
        KavitaCard(
            publicationId: publicationId,
            downloadId: downloadId,
            sourceId: subject.origin.sourceId,
            libraryId: subject.origin.libraryId,
            seriesId: subject.series.id,
            chapterId: subject.chapter.id,
            seriesName: subject.series.name,
            // The card's name is written straight over `Publication.displayTitle` when the
            // download is adopted, so it has to be the shelf's name and not the raw one.
            chapterName: KavitaContributor.title(of: subject.chapter, in: subject.series),
            summary: subject.metadata?.summary,
            people: subject.metadata?.people ?? [],
            subjects: subject.metadata?.subjects ?? [],
            releaseYear: subject.metadata?.releaseYear ?? 0,
            ageRating: subject.metadata?.ageRating ?? 0,
            publicationStatus: subject.metadata?.publicationStatus ?? -1
        )
    }
}
