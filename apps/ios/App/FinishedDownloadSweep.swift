import Foundation

import LibraryFeature
import Persistence
import ReaderFeature
import StoryArcCore

/// The sweep that takes a finished publication's download off the device, and D7's two
/// end-screen actions over the same download.
///
/// The other half of ``StoryArcApp``, split out because Swift's `private` is file-scoped
/// and the app file is at the length the linter allows. `LibraryModel` is divided the same
/// way and for the same reason.
extension StoryArcApp {
    /// Cheap to build: it wraps `UserDefaults.standard` and holds nothing of its own.
    private var cleanupChoices: CleanupChoices { CleanupChoices() }

    /// Takes a finished publication's download off the device, reversibly.
    ///
    /// First whatever the reader asked for on an end screen (D7), sweep or no sweep;
    /// then, with the sweep on, one finished download the reader did not keep.
    func sweepFinishedDownload() async {
        for id in cleanupChoices.takeRemovals() {
            remove(id)
        }
        guard settings.removeDownloadsAfterFinishing else { return }
        let library = DownloadQueue.shared().library

        // Asked of the store one path at a time, and awaited: `ProgressStore` is an actor,
        // and a predicate that could not await it would answer "not finished" to everything
        // and sweep nothing, for ever, silently.
        var done: Set<String> = []
        for download in library.finished {
            let path = downloadStore.location(of: download).path
            let record = try? await progress?.progress(
                for: PublicationIdentity(normalizedPath: path)
            )
            if record?.isFinished == true { done.insert(path) }
        }

        let finished = downloadStore.finishedDownload(
            in: library,
            isKept: cleanupChoices.isKept
        ) { done.contains($0) }
        guard let finished else { return }
        remove(finished.id)
    }

    /// What the end screen offers about `publication`'s download — `nil` when it was
    /// never one. See ``DownloadCleanupOffer``. Both actions only record the choice; the
    /// sweep acts on it when the reader closes, where its undo can be seen.
    func downloadCleanupOffer(for publication: Publication) -> DownloadCleanupOffer? {
        guard downloads[publication.id] != nil else { return nil }
        let id = publication.id
        let isSweeping = settings.removeDownloadsAfterFinishing
        return DownloadCleanupOffer(
            isRemovedOnClose: { cleanupChoices.isRemovedOnClose(id, automaticCleanupIsOn: isSweeping) },
            onRemove: { cleanupChoices.removeOnClose(id) },
            onKeep: { cleanupChoices.keep(id) }
        )
    }

    /// Through the shared queue, which is the only writer of the download store. A removal
    /// written to the store directly comes back at the queue's next save.
    ///
    /// Returns what it took, which the sweep ignores and ``removeFinished(_:)`` — the
    /// storage-full hold's own remedy — hands back to the free-space sheet.
    @discardableResult
    private func remove(_ id: Download.ID) -> RemovedDownload? {
        let queue = DownloadQueue.shared()
        guard let taken = queue.removeAfterFinishing(id) else { return nil }

        downloads = queue.library
        removedDownload?.settle()
        removedDownload = taken

        Task {
            try? await Task.sleep(for: .seconds(10))
            guard removedDownload?.download.id == taken.download.id else { return }
            taken.settle()
            removedDownload = nil
        }
        return taken
    }

    /// Lets the storage-full hold's own sheet take a finished download off the device,
    /// through the same queue and the same ten-second undo as every other removal.
    func removeFinished(_ download: Download) -> RemovedDownload? {
        remove(download.id)
    }

    /// Puts a download ``removeFinished(_:)`` took back, undoing it.
    func restoreFinished(_ removed: RemovedDownload) {
        DownloadQueue.shared().restore(removed)
        downloads = DownloadQueue.shared().library
        if removedDownload?.download.id == removed.download.id { removedDownload = nil }
    }
}
