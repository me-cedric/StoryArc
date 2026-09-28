import Foundation

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
    private var keptFromCleanup: KeptFromCleanup { KeptFromCleanup() }

    /// Takes a finished publication's download off the device, reversibly.
    func sweepFinishedDownload() async {
        let library = downloadStore.library()

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
            isKept: keptFromCleanup.contains
        ) { done.contains($0) }
        guard let finished else { return }
        remove(finished.id, from: library)
    }

    /// D7: the end screen's "Remove download" action, when automatic cleanup is off. The
    /// same removal the sweep does, done now rather than waited for.
    func removeDownloadNow(_ id: Download.ID) {
        remove(id, from: downloadStore.library())
    }

    /// D7: the end screen's "Keep" action, when automatic cleanup is on. The sweep skips
    /// this download from here on.
    func keepDownloadFromCleanup(_ id: Download.ID) {
        keptFromCleanup.keep(id)
    }

    /// What the end screen offers about `publication`'s download — `nil` when it was
    /// never one. See ``DownloadCleanupOffer``.
    func downloadCleanupOffer(for publication: Publication) -> DownloadCleanupOffer? {
        guard downloads[publication.id] != nil else { return nil }
        return DownloadCleanupOffer(
            automaticCleanupIsOn: settings.removeDownloadsAfterFinishing,
            onRemove: { removeDownloadNow(publication.id) },
            onKeep: { keepDownloadFromCleanup(publication.id) }
        )
    }

    private func remove(_ id: Download.ID, from library: DownloadLibrary) {
        guard let outcome = downloadStore.removeAfterFinishing(id, from: library) else { return }

        downloads = outcome.library
        removedDownload?.settle()
        removedDownload = outcome.removed

        let taken = outcome.removed
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard removedDownload?.download.id == taken.download.id else { return }
            taken.settle()
            removedDownload = nil
        }
    }
}
