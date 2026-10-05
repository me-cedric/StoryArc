public import Foundation
internal import Formats
internal import Persistence
public import StoryArcCore

/// What happens to a download when its transfer ends.
///
/// Split out of ``DownloadQueue`` for the same reason ``DownloadQueueHolds`` was: that file
/// reached the 400-line cap this project enforces, and the seam was already there. The
/// queue proper decides *what runs*; this is what a finished, corrupt, or failed transfer
/// becomes — where the bytes land, whether they are a publication at all, and who is told.
extension DownloadQueue {
    /// Moves a finished transfer into the download store and records it.
    ///
    /// Shared by the ordinary path and by adoption: a transfer that outlived the caller
    /// that asked for it has to end up in exactly the state one that did not would.
    func land(
        _ download: Download,
        from temporary: URL,
        seriesHint: String? = nil
    ) async throws -> URL {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        try store.prepare()
        let typed = try await typing(download, from: temporary)
        let file = store.location(of: typed)
        // The download's own folder, not just the store's: the id is a directory now.
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        DownloadStore.protect(file)
        // The transfer this token described is over. Left behind, it would be offered to the
        // next download of the same publication, which would carry on a transfer that has
        // already finished.
        try? FileManager.default.removeItem(at: store.resumeData(of: typed))
        // Indexing *is* the verification. `offline-downloads` requires integrity to be
        // checked "before it is marked available offline", and with no checksum from the
        // server the honest check is whether the bytes are a publication this app can
        // open. A truncated archive fails here, not at the first page turn.
        _ = try await PublicationIndexer.index(fileAt: file, catalogueSeries: seriesHint)
        // The size comes from the file now rather than from a buffer, because the bytes
        // never passed through one: the system wrote them straight to disk.
        let written = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        // The transfer this token was handed in for is over. A session token kept past the
        // request it authorised is a secret with no reason left to exist.
        given[typed.id] = nil
        library = library
            .typing(typed.id, as: typed.mediaType)
            .advancing(typed.id, downloaded: written, expected: written)
            .marking(typed.id, as: .finished)
        store.save(library)
        return file
    }

    /// The same download, with the media type the bytes actually have.
    ///
    /// **The destination's extension is chosen before the file lands, and one source cannot
    /// state it in time.** `offline-downloads` 1.9: Kavita serves comics and books from one
    /// `Download/chapter` route and names the type only in the response, so a chapter is
    /// enqueued with an empty media type. Where the record names no format this asks the
    /// bytes, which is the one answer that cannot be a guess — and a guess here is what
    /// wrote an EPUB under `.cbz` and handed it to the comic reader.
    ///
    /// A record that already names a format is left exactly as it is, so an OPDS download
    /// still lands under the type its acquisition link declared. The sniff costs one read of
    /// the temporary file's first pages and only for a record that has nothing to say.
    private func typing(_ download: Download, from temporary: URL) async throws -> Download {
        guard DownloadStore.extension(for: download.mediaType) == "bin",
              let sniffed = try? await PublicationIndexer.index(fileAt: temporary).format.mediaType
        else { return download }
        var typed = download
        typed.mediaType = sniffed
        return typed
    }

    /// Records that the bytes arrived and were not a publication.
    ///
    /// The corrupt file goes either way. On the re-queue it has to, because the next
    /// attempt writes to the same path and half a comic left there is what the storage
    /// total would count; on the second failure it has to for the same reason ``fail`` has
    /// always removed it. ``DownloadLibrary/failingVerification(_:reason:)`` decides which
    /// of the two this is, and that rule is asserted rather than living here.
    func failVerification(_ id: Download.ID, reason: String) {
        library = library.failingVerification(id, reason: reason)
        if let store, let download = library[id] {
            store.remove(download)
        }
        store?.save(library)
        // Only said out loud when it is actually over. A download quietly being fetched a
        // second time is not something to put on screen.
        if case .failed = library[id]?.state { lastFailure = reason }
    }

    func fail(_ id: Download.ID, reason: String, retryable: Bool = true) {
        library = retryable
            ? library.failing(id, reason: reason)
            // Marked as though every attempt were spent, so the queue stops asking and the
            // reader sees the reason rather than a spinner that returns twice more.
            : library.marking(
                id,
                as: .failed(reason: reason, attempts: DownloadLibrary.attemptLimit)
            )
        if let store, let download = library[id], !DownloadLibrary.shouldRetry(download) {
            // The whole directory, not the one file: a stem this build did not choose is
            // still this download's bytes, and leaving them is what made the storage total lie.
            //
            // Only once nothing is going to ask for the rest of them. The attempt after the
            // backoff resumes from the token beside the record, and deleting the directory
            // here is what made a dropped connection restart at zero.
            store.remove(download)
        }
        store?.save(library)
        lastFailure = reason
    }

    /// Hands the result to whoever was waiting to read it.
    func finish(_ id: Download.ID, with file: URL?) {
        for continuation in waiting.removeValue(forKey: id) ?? [] {
            continuation.resume(returning: file)
        }
    }
}
