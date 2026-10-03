package app.storyarc.feature.library

import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewModelScope
import app.storyarc.core.model.Publication
import kotlinx.coroutines.launch

/**
 * The seven actions a publication offers, wherever it is drawn.
 *
 * `library-browsing`'s *A publication's actions wherever it is drawn*: "the same actions ...
 * in every one of those places: open, mark as read or mark as unread, start from the
 * beginning, add to a shelf, download or remove the download, and show the publication's
 * details", with a seventh -- removing it from the shelf the menu was opened on -- "offered
 * only where there is one". iOS's `PublicationActionMenuTests` asks the same ordered
 * question of the same six-or-seven shape.
 */
enum class PublicationMenuAction {
    OPEN,
    MARK,
    RESTART,
    ADD_TO_SHELF,
    DOWNLOAD,
    REMOVE_DOWNLOAD,
    REMOVE_FROM_SHELF,
    SHOW_DETAILS,
}

/**
 * The one list builder every surface asks, so a page offering the menu cannot drift from
 * what another page offers.
 *
 * Pure and free of Compose, for the reason [DownloadOffer] and [RestartOffer] already are: a
 * rule asked by a menu on every long press is worth asserting directly, by a test that does
 * not have to compose one. [PublicationActionMenu] (the composable below) asks this and
 * nothing else for its order and its gating, so the two cannot answer differently.
 */
object PublicationActionMenuItems {
    fun of(
        offersRestart: Boolean,
        downloadOffer: DownloadOffer,
        offersRemoveFromShelf: Boolean,
    ): List<PublicationMenuAction> = buildList {
        add(PublicationMenuAction.OPEN)
        add(PublicationMenuAction.MARK)
        if (offersRestart) add(PublicationMenuAction.RESTART)
        add(PublicationMenuAction.ADD_TO_SHELF)
        when (downloadOffer) {
            DownloadOffer.Download -> add(PublicationMenuAction.DOWNLOAD)
            DownloadOffer.Remove -> add(PublicationMenuAction.REMOVE_DOWNLOAD)
            DownloadOffer.None -> {}
        }
        if (offersRemoveFromShelf) add(PublicationMenuAction.REMOVE_FROM_SHELF)
        add(PublicationMenuAction.SHOW_DETAILS)
    }
}

/**
 * The menu itself: a long press opens this, anchored to the cell, on every surface that
 * draws a publication.
 *
 * **One call wraps the whole action, the way iOS's `PublicationActionMenu` wraps
 * `AddToShelfMenu` rather than repeating what [AddToShelfSheet] already gets right.** *Add to
 * shelf* opens that same sheet, with its own mark/restart/download rows turned off through
 * [AddToShelfSheet]'s `offersDownloadAction` and its nullable callbacks -- this menu already
 * offered them, and a reader who dismisses one must not meet it again in the next.
 *
 * A `DropdownMenu`, not the `ModalBottomSheet` every surface opened before this: a long press
 * already carries the platform's own haptic through `combinedClickable`, which is why no
 * surface wiring this in needs to ask for one again -- see `Haptics.kt`'s own note on the
 * point.
 *
 * @param onDismissRequest closes the whole menu, including the shelf sheet behind it. Every
 *   surface wires this to clearing the one `Publication?` state it opened the menu from.
 * @param onOpen the action the cell's own tap already performs on this surface -- a resume
 *   on the continue-reading row, the publication's page everywhere else. `library-browsing`
 *   still asks for the row because a menu reached without ever tapping the cover is the one
 *   place a reader with a screen reader meets it.
 * @param onShowDetails always the publication's own page, whatever [onOpen] does here -- the
 *   two are the same action only where [onOpen] already is that page.
 */
@Composable
fun PublicationActionMenu(
    publication: Publication,
    viewModel: LibraryViewModel,
    onDismissRequest: () -> Unit,
    onOpen: () -> Unit,
    onMark: (Publication, Boolean) -> Unit,
    onRestart: () -> Unit,
    onShowDetails: () -> Unit,
    onAddToServerList: (suspend (Publication, ServerList) -> Boolean)? = null,
    onRemoveFromShelf: (() -> Unit)? = null,
) {
    var isShelfOpen by remember { mutableStateOf(false) }

    val finished = viewModel.finishedPublications().contains(publication.id)
    val hasProgress = viewModel.readFraction(publication) != null
    val offersRestart = RestartOffer.isOffered(
        publicationCount = 1,
        hasSomethingToClear = finished || hasProgress,
        isWired = true,
    )
    val downloadOffer = DownloadOffer.of(
        publication,
        isKept = viewModel.isOnDevice(publication),
        isLocalFile = isOnDevice(viewModel.location(publication)),
        isQueueableRemote = PublicationActions.isQueueableRemote(publication),
    )

    val items = PublicationActionMenuItems.of(
        offersRestart = offersRestart,
        downloadOffer = downloadOffer,
        offersRemoveFromShelf = onRemoveFromShelf != null,
    )

    DropdownMenu(expanded = !isShelfOpen, onDismissRequest = onDismissRequest) {
        items.forEach { action ->
            DropdownMenuItem(
                text = { Text(stringResource(action.label(finished))) },
                onClick = {
                    when (action) {
                        PublicationMenuAction.OPEN -> {
                            onDismissRequest()
                            onOpen()
                        }

                        PublicationMenuAction.MARK -> {
                            onDismissRequest()
                            onMark(publication, !finished)
                        }

                        PublicationMenuAction.RESTART -> {
                            onDismissRequest()
                            onRestart()
                        }

                        PublicationMenuAction.ADD_TO_SHELF -> isShelfOpen = true

                        PublicationMenuAction.DOWNLOAD -> {
                            onDismissRequest()
                            viewModel.viewModelScope.launch {
                                viewModel.keepOffline(setOf(publication.id))
                            }
                        }

                        PublicationMenuAction.REMOVE_DOWNLOAD -> {
                            onDismissRequest()
                            viewModel.forgetKept(setOf(publication.id))
                        }

                        PublicationMenuAction.REMOVE_FROM_SHELF -> {
                            onDismissRequest()
                            onRemoveFromShelf?.invoke()
                        }

                        PublicationMenuAction.SHOW_DETAILS -> {
                            onDismissRequest()
                            onShowDetails()
                        }
                    }
                },
            )
        }
    }

    if (isShelfOpen) {
        AddToShelfSheet(
            viewModel = viewModel,
            publications = listOf(publication),
            onDismiss = {
                isShelfOpen = false
                onDismissRequest()
            },
            onAddToServerList = onAddToServerList,
            offersDownloadAction = false,
        )
    }
}

/** The word on the row. `MARK` is the one case that depends on state. */
private fun PublicationMenuAction.label(isFinished: Boolean): Int = when (this) {
    PublicationMenuAction.OPEN -> R.string.library_action_open
    PublicationMenuAction.MARK -> if (isFinished) R.string.library_mark_unread else R.string.library_mark_read
    PublicationMenuAction.RESTART -> R.string.library_restart
    PublicationMenuAction.ADD_TO_SHELF -> R.string.shelves_add_to
    PublicationMenuAction.DOWNLOAD -> R.string.catalogue_acquire_download
    PublicationMenuAction.REMOVE_DOWNLOAD -> R.string.downloads_remove
    PublicationMenuAction.REMOVE_FROM_SHELF -> R.string.library_action_remove_from_shelf
    PublicationMenuAction.SHOW_DETAILS -> R.string.library_action_show_details
}
