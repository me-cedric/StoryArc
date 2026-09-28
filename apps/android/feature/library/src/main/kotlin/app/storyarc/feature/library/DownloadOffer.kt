package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat

/**
 * Whether a publication's copy can be added to, or taken off, the device.
 *
 * A folder of images is already on the device and has no single file to copy, and a
 * publication no decoder will open has nothing worth fetching either -- offering either
 * action anyway would be a control that reports success and changes nothing. iOS's
 * `PublicationActions.canDownload` is the same rule.
 */
object PublicationActions {
    fun canDownload(publication: Publication): Boolean =
        publication.isOpenable && publication.format != PublicationFormat.IMAGE_FOLDER
}

/**
 * What a download action offers: to fetch a copy, to remove one, or neither.
 *
 * A named value rather than two booleans compared inline, so a menu asks one question and a
 * test can state all three answers without a composition. iOS's `DownloadOffer` is the same
 * three cases.
 *
 * `isLocalFile`: the menu's download is [LibraryViewModel.keepOffline], which copies a file
 * that is already on this device. A row whose bytes are on a server has no such file, so the
 * copy is skipped and nothing happens. The menu does not offer a download it cannot deliver.
 */
sealed class DownloadOffer {
    object Download : DownloadOffer()
    object Remove : DownloadOffer()
    object None : DownloadOffer()

    companion object {
        fun of(publication: Publication, isKept: Boolean, isLocalFile: Boolean): DownloadOffer = when {
            isKept -> Remove
            isLocalFile && PublicationActions.canDownload(publication) -> Download
            else -> None
        }
    }
}
