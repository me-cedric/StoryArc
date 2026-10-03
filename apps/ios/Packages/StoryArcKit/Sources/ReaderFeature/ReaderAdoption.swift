public import Foundation

internal import Formats
internal import Persistence
internal import StoryArcCore

/// Reads from the copy that has just arrived, without interrupting the reader.
///
/// `offline-downloads`' *Reading while downloading*: a publication opened by streaming
/// "switches to the local copy when the download completes, without interrupting reading".
///
/// Its own file because ``ReaderModel`` is at its line cap, and a file that may not grow is a
/// file where the next thing is added somewhere else. Android's `ReaderAdoption.kt` is the
/// same two steps in the same order.
///
/// Nothing here touches the page list, the position, the decoded pages or the thumbnails. The
/// whole switch is ``AdoptingArchive/adopt(_:)`` taking a new source, and the reader is never
/// told — which is what "without interrupting" means.
extension ReaderModel {

    /// How often the store is asked whether the copy has landed.
    ///
    /// A poll rather than a listener, and the interval is what makes that honest: a finished
    /// download is a JSON read of a file the app wrote, so asking every two seconds costs
    /// less than the observation machinery would, and nothing on iOS publishes that event
    /// today. Two seconds is also under the time a reader spends on a page, so the switch
    /// happens between page turns rather than during one.
    private static var pollInterval: Duration { .seconds(2) }

    /// Watches for the local copy while this reader is streaming, and takes it when it lands.
    ///
    /// Returns as soon as the reader is not streaming, so a publication opened from disk pays
    /// nothing for this at all.
    ///
    /// Started by ``ReaderLifecycle`` in its own `.task`, parallel with the one that calls
    /// `open(maxPixelSize:)` — so this can run before `open` has set ``ReaderModel/archive``
    /// at all. Waiting for it here, rather than reading it once and returning when it is
    /// still nil, is what makes the watch reach a publication that opens successfully: read
    /// once, this returned before there was ever anything to watch, and a completed
    /// background download sat in the store for ever with nobody adopting it.
    ///
    /// Not `public`: `DownloadStore` is `Persistence`'s own internal type here (this file
    /// imports it `internal`), and the only caller outside this file is ``ReaderLifecycle``,
    /// in the same module. A test reaches it through `@testable import`.
    ///
    /// - Parameter store: defaults to the app's own store. A test passes its own isolated
    ///   one — the same reason ``ReaderModel/init(publication:url:progress:preferences:canCurl:)``
    ///   takes `progress` rather than reading a shared instance.
    func adoptTheCopyWhenItArrives(store: DownloadStore = DownloadStore()) async {
        guard ReadingAddress.isStreamed(url) else { return }
        while !Task.isCancelled {
            guard let reading = archive as? AdoptingArchive else {
                // Not open yet, or a stream that never opened at all — `offline-downloads`'
                // dl-core 1.7: a server with no range support leaves `archive` nil for good,
                // and `open(maxPixelSize:)` set `isWaitingForDownload` instead of `failure`
                // for exactly this reason. There is still nothing to adopt *into*, so the
                // local copy is opened fresh the moment it lands.
                if isWaitingForDownload,
                   let arrived = ReadingAddress.arrived(at: url, in: store.library()),
                   await openLocalCopyAfterWaiting(
                       store.location(for: arrived.id, mediaType: arrived.mediaType, title: arrived.title)
                   ) {
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
                continue
            }
            if let arrived = ReadingAddress.arrived(at: url, in: store.library()),
               // Where the store put the bytes, computed from the record the same way the
               // queue computed it when it wrote them.
               await adopt(
                   store.location(for: arrived.id, mediaType: arrived.mediaType, title: arrived.title),
                   into: reading
               ) {
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// Opens the arrived file and hands it to the archive, or leaves the stream alone.
    ///
    /// Refused rather than thrown: a local copy that will not open is not a reason to take a
    /// working stream away from somebody mid-page.
    private func adopt(_ local: URL, into reading: AdoptingArchive) async -> Bool {
        guard let opened = try? await ComicArchiveOpener.open(fileAt: local) else { return false }
        return reading.adopt(opened)
    }

    /// Opens the file that just finished downloading, after the stream never opened at all.
    ///
    /// Unlike ``adopt(_:into:)``, there is no existing archive to swap bytes into — the open
    /// in `ReaderModel.open(maxPixelSize:)` never produced one. This runs the same success
    /// path a working stream would have, through ``applyOpenedArchive(_:)``, and always clears
    /// `isWaitingForDownload`: a copy that will not open either is a real failure now that
    /// there is nothing left to wait for.
    private func openLocalCopyAfterWaiting(_ local: URL) async -> Bool {
        guard let opened = try? await ComicArchiveOpener.open(fileAt: local) else {
            isWaitingForDownload = false
            failure = String(localized: "reader.cannotOpen", bundle: .module, locale: .storyArc)
            return true
        }
        await applyOpenedArchive(opened)
        isWaitingForDownload = false
        return true
    }

    /// Puts a freshly opened archive in place: the page list, the designated cover, a
    /// recorded position, and the warm/colour side effects a successful
    /// `open(maxPixelSize:)` already ran. Shared with ``openLocalCopyAfterWaiting(_:)``, which
    /// reaches this from a stream that never opened at all.
    func applyOpenedArchive(_ opened: any ComicArchiveReading) async {
        let wrapped = AdoptingArchive(opened)
        archive = wrapped
        pages = wrapped.pages
        skippedPageCount = wrapped.skippedPageCount
        wideIndices = Set(wrapped.doublePageIndices)
        // Start at the designated cover when there is one. `publication-formats`
        // lets ComicInfo name a cover that is not page one, and opening on a
        // different page than the library showed would be disorienting.
        if let coverPath = publication.coverPath,
           let index = pages.firstIndex(where: { $0.path == coverPath }) {
            currentIndex = index
        }
        // A recorded position wins over the cover. `reading-progress` is about picking up
        // where you left off, and a book you are halfway through should not reopen at its
        // cover.
        //
        // Unless it is finished, which the same requirement singles out: reopening a
        // finished publication "starts at the beginning while retaining the finished
        // record". Dropping the override is the whole of it — the record is untouched, and
        // the beginning is where `currentIndex` already is.
        if let recorded = try? await progress?.progress(for: publication.identity),
           !recorded.isFinished,
           case let .page(index, _) = recorded.position,
           pages.indices.contains(index) {
            currentIndex = index
        }
        await warm(around: currentIndex)
        await deriveCoverColours()
    }
}
