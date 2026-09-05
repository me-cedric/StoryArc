package app.storyarc

import androidx.annotation.StringRes
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.ImportedCopies

/**
 * Which question a reader is being asked when they take something off this device.
 *
 * The Downloads destination had one confirmation for every act. *Stop*, on a row still
 * arriving, put up *Remove this download?* — "This deletes the copy of Harbour Lights 03 on
 * this device. Your reading position is kept, and it can be downloaded again." There is no
 * copy on the device and there is no reading position: the reader is cancelling something in
 * flight, and both halves of the sentence they were shown were false. The September sweep
 * photographed the iOS twin of it as `ios-downloads-stop-confirm.png`.
 *
 * Stopping and removing are near neighbours in the code — both end with the record gone and
 * the bytes swept aside — and that is exactly why the *words* have to be told apart
 * deliberately rather than inherited. This is where the telling apart happens, and the
 * ordering below is what its tests pin.
 *
 * It is iOS's `DownloadQueueRemoval`, member for member; that file's header carries the
 * same reasoning and its tests carry the same cases.
 */
internal enum class DownloadQueueRemoval {

    /**
     * Still arriving. Nothing to delete, no place to keep, nothing to say about an original —
     * only that the transfer stops and can be started again.
     */
    STOPPING,

    /**
     * On the device, fetched from a source. The copy goes and the reading position stays,
     * which is the sentence the old string was actually written for.
     */
    REMOVING,

    /**
     * On the device, copied in by the reader. `local-library` asks this one to name the space
     * it frees "and state that the original file elsewhere is untouched", because an import
     * is the one row here with an original somewhere else.
     */
    REMOVING_IMPORT,
    ;

    /** What the dialog asks. */
    @get:StringRes
    val titleRes: Int
        get() = when (this) {
            STOPPING -> R.string.downloads_stop_title
            REMOVING, REMOVING_IMPORT -> R.string.downloads_remove_title
        }

    /**
     * What the destructive button is called.
     *
     * Named for the act rather than for the screen it is on. *Remove download* under *Stop
     * this download?* would be the same mismatch one control further along.
     */
    @get:StringRes
    val confirmRes: Int
        get() = when (this) {
            STOPPING -> R.string.downloads_stop_confirm
            REMOVING, REMOVING_IMPORT -> R.string.downloads_remove
        }

    companion object {

        /**
         * What this download's confirmation is about.
         *
         * **Landed first, imported second.** An import is written into the record as
         * `Queued` and marked finished on the next line, so a record caught between the two
         * is an import that has not landed — and the import sentence would promise to free a
         * size the reader never had. Asking whether it has arrived before asking where it
         * came from is what keeps that impossible.
         */
        fun of(download: Download): DownloadQueueRemoval =
            if (!download.state.isFinished) {
                STOPPING
            } else if (ImportedCopies.isImported(download)) {
                REMOVING_IMPORT
            } else {
                REMOVING
            }
    }
}
