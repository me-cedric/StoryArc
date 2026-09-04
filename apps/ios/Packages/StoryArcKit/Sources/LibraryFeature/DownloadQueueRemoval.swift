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
/// **Android has the identical defect**, in `DownloadsParts.kt`'s `RemoveDownloadDialog`
/// and the same four `downloads_remove_*` strings. It is untouched here: this change is
/// iOS-only by its brief.
public enum DownloadQueueRemoval {

    /// The three sentences, which are three different promises.
    public enum Confirmation: Sendable, Equatable {
        /// Still arriving. Nothing to delete, no place to keep, nothing to say about an
        /// original — only that the transfer stops and can be started again.
        case stopping

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
    /// **Landed first, imported second.** An import is written into the record as `queued`
    /// and marked finished on the next line, so a record caught between the two is an
    /// import that has not landed — and the import sentence would promise to free a size
    /// the reader never had. Asking whether it has arrived before asking where it came from
    /// is what keeps that impossible.
    public static func confirmation(for download: Download) -> Confirmation {
        guard download.state.isFinished else { return .stopping }
        return ImportedCopies.isImported(download) ? .removingImport : .removing
    }
}
