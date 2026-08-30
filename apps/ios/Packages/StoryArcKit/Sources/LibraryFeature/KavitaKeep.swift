internal import Foundation

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

    /// Fetches a chapter, files it as a download, and writes down what the server said.
    ///
    /// Nil when any step fails, and deliberately without a half-kept result: a record whose
    /// bytes are not there reads to a reader as a library that lost their book, which is the
    /// failure ``DownloadStore`` exists to make impossible.
    static func keep(
        _ subject: Subject,
        client: KavitaClient,
        downloads: DownloadStore = DownloadStore(),
        cards: KavitaCardStore = KavitaCardStore(),
        progress: KavitaProgressStore
    ) async -> Kept? {
        let (chapter, series, origin, sourceID) =
            (subject.chapter, subject.series, subject.origin, subject.sourceID)

        let title = chapter.displayName.isEmpty
            ? "\(series.name) \(chapter.number)"
            : chapter.displayName

        guard let fetched = try? await client.chapter(chapter.id),
              let staged = kavitaCacheFile(
                  chapterId: chapter.id,
                  mediaType: fetched.mediaType,
                  named: title
              ),
              (try? fetched.bytes.write(to: staged, options: .atomic)) != nil,
              let mediaType = await type(of: fetched, at: staged)
        else { return nil }

        // The record's own identifier, and therefore the directory the bytes go in.
        //
        // The server's chapter, not the file's identity. It was the file's, and driving it
        // showed why that cannot work: the identity of a publication is its path, the path
        // is chosen from the identity, and the file the reader ends up with is at a *third*
        // path — so the card was filed under the staging directory and the shelf, indexing
        // the download, never found it. A catalogue download has the same shape and solved
        // it the same way: `Download.id` is what the *source* calls the thing.
        let identifier = "kavita:\(origin.sourceId):\(chapter.id)"
        let destination = downloads.location(
            for: identifier,
            mediaType: mediaType,
            title: title
        )
        guard let bytes = file(staged, to: destination, in: downloads) else { return nil }

        // Indexed where it landed, not where it was staged. This is the identity the library
        // will compute when it walks the download tree, which is what the card has to be
        // filed under for the server's metadata to reach the shelf.
        guard var publication = try? await PublicationIndexer.index(
            fileAt: destination,
            catalogueSeries: series.name
        ) else { return nil }
        // `library-browsing` attributes a download to the source its record names, which is
        // what puts a kept chapter on the one shelf that spans every source.
        publication.sourceID = sourceID

        // No secret in it: Kavita takes the key as a bearer header on this route, not in the
        // query, so what is written down is a path and a chapter number.
        let remote = await client.address.chapterURL(chapter.id) ?? destination
        downloads.save(
            downloads.library().queueing(
                Download(
                    id: identifier,
                    sourceID: sourceID,
                    title: title,
                    remote: remote,
                    mediaType: mediaType,
                    state: .finished,
                    expectedBytes: bytes,
                    downloadedBytes: bytes,
                    completedAt: Date()
                )
            )
        )

        cards.save(card(publication.id, downloadId: identifier, subject))
        // The same note the open path leaves, and for the same reason: the reader opens a
        // file and knows nothing about servers, so this is what lets the position get home.
        progress.remember(origin, for: publication.id)

        return Kept(publication: publication, file: destination)
    }

    /// What the file is, from the server's word or from the bytes.
    ///
    /// The server's declaration is preferred and is usually there. Indexing the staged copy
    /// is the fallback for a server that sent no type, because the extension the download is
    /// written under decides which reader opens it.
    private static func type(of fetched: KavitaFile, at staged: URL) async -> String? {
        if let declared = fetched.mediaType { return declared }
        return try? await PublicationIndexer.index(fileAt: staged).format.mediaType
    }

    /// Moves the staged bytes to where the store says they live, and reports what they weigh.
    ///
    /// Nil when the move failed, which is what makes a half-kept download impossible: the
    /// record is only written after this answers.
    private static func file(_ staged: URL, to destination: URL, in store: DownloadStore) -> Int64? {
        try? store.prepare()
        let manager = FileManager.default
        try? manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Replaced rather than refused, for the reason `KeepOffline` gives: a file left by a
        // removal that only got half way is not a reason to refuse the reader their comic.
        try? manager.removeItem(at: destination)
        guard (try? manager.moveItem(at: staged, to: destination)) != nil else { return nil }
        return Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// What the server said, in the shape that survives it going away.
    private static func card(
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
            chapterName: subject.chapter.displayName,
            summary: subject.metadata?.summary,
            people: subject.metadata?.people ?? [],
            subjects: subject.metadata?.subjects ?? [],
            releaseYear: subject.metadata?.releaseYear ?? 0
        )
    }
}
