internal import Persistence
public import StoryArcCore

/// Which question a reader is being asked when they take something off this device.
///
/// The Downloads destination had one confirmation for two acts. *Stop*, on a row still
/// arriving, put up *Remove this download?* — "This deletes the copy of Harbour Lights 03
/// on this device. Your reading position is kept, and it can be downloaded again." There is
/// no copy on the device and there is no reading position: the reader is cancelling
/// something in flight, and both halves of the sentence they were shown were false. The
/// September sweep photographed it as `ios-downloads-stop-confirm.png`.
///
/// Stopping and removing are near neighbours in the code — both end with the record gone
/// and the bytes swept aside — and that is exactly why the *words* have to be told apart
/// deliberately rather than inherited. This is where the telling apart happens, and the
/// ordering below is what its tests pin.
///
/// **Android had the identical defect, and fixed it first.** `DownloadsParts.kt`'s
/// `RemoveDownloadDialog` asked the same wrong question over the same four
/// `downloads_remove_*` strings; its `DownloadQueueRemoval.kt` is now this file member for
/// member, and `DownloadQueueRemovalTest.kt` is the suite beside this one case for case.
/// The fourth case below landed there a day before it landed here, and for the same reason:
/// a queue row that offers *Remove* on a failed transfer needs a sentence that neither
/// interrupts anything nor promises a copy. iOS follows.
public enum DownloadQueueRemoval {

    /// The four sentences, which are four different promises.
    public enum Confirmation: Sendable, Equatable {
        /// Still arriving. Nothing to delete, no place to keep, nothing to say about an
        /// original — only that the transfer stops and can be started again.
        case stopping

        /// Stopped by itself and being cleared out of the queue. The reader pressed *Remove*
        /// and not *Stop*, so the question is a removal — of a download that never landed,
        /// which is why it can borrow neither ``removing``'s sentence about a copy and a
        /// reading position nor ``stopping``'s about a transfer being interrupted. The
        /// transfer stopped three attempts ago.
        case discarding

        /// On the device, fetched from a source. The copy goes and the reading position
        /// stays, which is the sentence the old string was actually written for.
        case removing

        /// On the device, copied in by the reader. `local-library` asks this one to name
        /// the space it frees "and state that the original file elsewhere is untouched",
        /// because an import is the one row here with an original somewhere else.
        case removingImport
    }

    /// What this download's confirmation is about.
    ///
    /// **Landed first, then failed, then where it came from.** An import is written into the
    /// record as `queued` and marked finished on the next line, so a record caught between
    /// the two is an import that has not landed — and the import sentence would promise to
    /// free a size the reader never had. Asking whether it has arrived before asking anything
    /// else is what keeps that impossible; asking whether it failed before asking where it
    /// came from is what keeps a failed import from being offered the same false promise.
    ///
    /// A paused download is a ``Confirmation/stopping``, not a ``Confirmation/discarding``:
    /// its row still offers *Stop* rather than *Remove*, for the reason `DownloadQueueRow`
    /// gives — a retry from that screen could re-queue it only to have it pause again.
    public static func confirmation(for download: Download) -> Confirmation {
        if download.state.isFinished {
            return ImportedCopies.isImported(download) ? .removingImport : .removing
        }
        if case .failed = download.state { return .discarding }
        return .stopping
    }
}
