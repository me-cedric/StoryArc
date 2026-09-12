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
    public func adoptTheCopyWhenItArrives() async {
        guard ReadingAddress.isStreamed(url), let reading = archive as? AdoptingArchive else { return }
        let store = DownloadStore()
        while !Task.isCancelled {
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
}
