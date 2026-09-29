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
    private var cleanupChoices: CleanupChoices { CleanupChoices() }

    /// Takes a finished publication's download off the device, reversibly.
    ///
    /// First whatever the reader asked for on an end screen (D7), sweep or no sweep;
    /// then, with the sweep on, one finished download the reader did not keep.
    func sweepFinishedDownload() async {
        for id in cleanupChoices.takeRemovals() {
            remove(id, from: downloadStore.library())
        }
        guard settings.removeDownloadsAfterFinishing else { return }
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
            isKept: cleanupChoices.isKept
        ) { done.contains($0) }
        guard let finished else { return }
        remove(finished.id, from: library)
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
