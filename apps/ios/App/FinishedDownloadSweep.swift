import Foundation

import Persistence
import StoryArcCore

/// The sweep that takes a finished publication's download off the device.
///
/// The other half of ``StoryArcApp``, split out because Swift's `private` is file-scoped
/// and the app file is at the length the linter allows. `LibraryModel` is divided the same
/// way and for the same reason.
extension StoryArcApp {

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

        let finished = downloadStore.finishedDownload(in: library) { done.contains($0) }
        guard let finished,
              let outcome = downloadStore.removeAfterFinishing(finished.id, from: library)
        else { return }

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
