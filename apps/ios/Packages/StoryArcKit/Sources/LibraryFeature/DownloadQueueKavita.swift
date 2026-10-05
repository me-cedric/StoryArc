public import Foundation

public import Catalogue
internal import Persistence
public import StoryArcCore

/// Downloading a Kavita chapter, which is a download like any other and was not one.
///
/// `offline-downloads` 1.9: keeping a chapter fetched the whole body into a `Data`, wrote it
/// to a cache file and moved it into the download store by hand. So a kept chapter had no row
/// in the downloads view, no pause, no resume, no retry and no share of the concurrency
/// bound — the four things *Queue management* asks for — and a six-hundred-megabyte collected
/// edition was a six-hundred-megabyte buffer. The queue already streams a transfer straight to
/// disk through ``BackgroundTransfers``, so the fix is to let a chapter in rather than to build
/// a second transfer beside it.
///
/// Its own entry point rather than a call to
/// ``DownloadQueue/enqueue(_:using:sourceID:overridingMeteredConnection:)``, because a chapter
/// is not an OPDS acquisition and differs in the two places that matter:
///
/// 1. **The credential is a session token, not the stored secret.** Kavita mints a short-lived
///    bearer token from the reader's API key, and
///    ``DownloadQueue/credentialResolver(store:sources:credentials:)`` reads the secure store,
///    where the key lives. So the caller, which already holds an authenticated `KavitaClient`,
///    hands the token in with the chapter.
/// 2. **The media type is not known yet.** One `Download/chapter` route serves comics and
///    books alike and names the type only in the response, so the record is enqueued with an
///    empty one and ``DownloadQueue/land(_:from:seriesHint:)`` writes what the bytes turn out
///    to be. Nothing guesses an extension here: an EPUB written under `.cbz` reaches the comic
///    reader, which spins for ever on a file it cannot page.
///
/// Android's `DownloadQueue.fetchChapter` is the same entry point.
extension DownloadQueue {
    /// This download's finished file, when there is one on disk.
    ///
    /// Keyed by the download's own id rather than by a catalogue entry, because a Kavita
    /// chapter has no entry. ``downloaded(_:sourceID:)`` resolves an entry to an id and then
    /// asks this.
    public func file(of id: Download.ID) -> URL? {
        guard let download = library[id], download.state.isFinished, let store else { return nil }
        let file = store.location(of: download)
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    /// Queues a Kavita chapter and waits for its file, as ``fetch(_:using:sourceID:overridingMeteredConnection:)``
    /// does for a catalogue entry.
    ///
    /// - Parameter id: the record's id, which is what the *source* calls the chapter —
    ///   `kavita:<source>:<chapter>`. The card and the fold are filed under it, so the caller
    ///   spells it rather than this.
    /// - Parameter credential: the bearer token for this one transfer. Held in memory until
    ///   the transfer ends, for the reason ``DownloadQueue/given`` gives.
    /// - Returns: the landed file, or `nil` when the transfer failed — the queue has recorded
    ///   the reason by then, so the caller says nothing more about it.
    public func fetchChapter(
        id: Download.ID,
        title: String,
        from remote: URL,
        sourceID: UUID?,
        credential: OpdsCredential,
        seriesHint: String? = nil
    ) async -> URL? {
        if let file = file(of: id) { return file }
        given[id] = credential
        if let seriesHint { hints[id] = seriesHint }
        if library[id] == nil {
            library = library.queueing(
                Download(
                    id: id,
                    sourceID: sourceID,
                    title: title,
                    remote: remote,
                    // Empty on purpose. The server states it in the response and
                    // ``land(_:from:seriesHint:)`` writes it down; see this file's own note.
                    mediaType: ""
                )
            )
            store?.save(library)
            pump()
        } else {
            // A chapter the reader asked for again after it failed or was paused. `queueing`
            // is a no-op once a record exists, and neither state resolves itself — the same
            // rule ``fetch(_:using:sourceID:overridingMeteredConnection:)`` follows.
            resume(id)
        }
        promote(id)
        return await withCheckedContinuation { continuation in
            waiting[id, default: []].append(continuation)
        }
    }
}
