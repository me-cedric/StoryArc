public import Foundation

public import StoryArcCore

/// A download taken off the device because its publication was finished.
///
/// `offline-downloads`: with the setting on, finishing a publication removes its download,
/// "its progress is kept, and the removal is undoable for 10 seconds". Undoable is the hard
/// part: a file already deleted can only be put back by downloading it again, which is not
/// an undo. So the file is moved aside and only deleted when the ten seconds are up.
public struct RemovedDownload: Sendable {
    public let download: Download
    /// Where the bytes are waiting, in case the reader changes their mind.
    public let aside: URL

    private let home: URL

    init(download: Download, aside: URL, home: URL) {
        self.download = download
        self.aside = aside
        self.home = home
    }

    /// Puts the download back, bytes and record together.
    public func undo(_ library: DownloadLibrary, in store: DownloadStore) -> DownloadLibrary {
        try? FileManager.default.moveItem(at: aside, to: home)
        let restored = library.queueing(download)
        store.save(restored)
        return restored
    }

    /// Lets it go. Called when nobody undid it.
    public func settle() {
        try? FileManager.default.removeItem(at: aside)
    }
}

extension DownloadStore {
    /// Where a download's bytes live, from the record alone.
    public func location(of download: Download) -> URL {
        location(
            for: download.id,
            extension: Self.extension(for: download.mediaType),
            named: download.title
        )
    }

    /// The first download whose file the reader has finished, if any.
    ///
    /// Matched by the file's own path rather than by the publication id. A download's id is
    /// whatever the catalogue called it; the progress record is written by the reader
    /// against the local file it opened, and this store is what knows those two are the
    /// same thing.
    ///
    /// An imported copy is never one of them. `offline-downloads` sweeps a download away
    /// because "the catalogue can be asked for it again", and nothing can be asked for an
    /// import — `local-library` promises the copy outlives the original, so deleting it on
    /// the last page would be the app breaking its own promise.
    public func finishedDownload(
        in library: DownloadLibrary,
        isFinished: (String) -> Bool
    ) -> Download? {
        library.finished.first {
            !ImportedCopies.isImported($0) && isFinished(location(of: $0).path)
        }
    }

    /// Takes a finished publication's download off the device, reversibly.
    ///
    /// Nil when there was nothing to remove, which is the common case: most publications a
    /// reader finishes were never downloaded.
    public func removeAfterFinishing(
        _ id: Download.ID,
        from library: DownloadLibrary
    ) -> (library: DownloadLibrary, removed: RemovedDownload)? {
        guard let download = library[id] else { return nil }
        let home = location(of: download)
        guard FileManager.default.fileExists(atPath: home.path) else { return nil }

        // Moved, not deleted. The record goes now so the library stops calling it
        // downloaded; the bytes wait until the undo window closes.
        let aside = home.appendingPathExtension("removing")
        try? FileManager.default.removeItem(at: aside)
        guard (try? FileManager.default.moveItem(at: home, to: aside)) != nil else { return nil }

        let without = library.removing(id)
        save(without)
        return (without, RemovedDownload(download: download, aside: aside, home: home))
    }
}
