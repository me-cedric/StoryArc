public import Foundation
internal import Formats
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
        let file = store.location(of: download)
        // The download's own folder, not just the store's: the id is a directory now.
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        // Indexing *is* the verification. `offline-downloads` requires integrity to be
        // checked "before it is marked available offline", and with no checksum from the
        // server the honest check is whether the bytes are a publication this app can
        // open. A truncated archive fails here, not at the first page turn.
        _ = try await PublicationIndexer.index(fileAt: file, catalogueSeries: seriesHint)
        // The size comes from the file now rather than from a buffer, because the bytes
        // never passed through one: the system wrote them straight to disk.
        let written = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        library = library
            .advancing(download.id, downloaded: written, expected: written)
            .marking(download.id, as: .finished)
        store.save(library)
        return file
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
        if let store, let download = library[id] {
            // The whole directory, not the one file: a stem this build did not choose is
            // still this download's bytes, and leaving them is what made the storage total lie.
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
