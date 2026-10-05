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
 * **The one shared builder, and nothing in it reaches a view model.** `home-screen` forbids
 * the home surface from holding one -- see `HomeScreen.kt`'s own `PublicationActionFacts` --
 * so the three facts a menu's gating needs ([markedFinished], [offersRestart], [downloadOffer])
 * arrive as plain values here, computed by whichever caller has a way to them.
 * [PublicationActionMenuTarget] is that caller for the library grid, the list and both shelf
 * pages, all of which do hold one; a page that does not computes the same three facts itself
 * and calls this directly, the way `HomeCoverRun` does.
 *
 * A `DropdownMenu`, not the `ModalBottomSheet` every surface opened before this: a long press
 * already carries the platform's own haptic through `combinedClickable`, which is why no
 * surface wiring this in needs to ask for one again -- see `Haptics.kt`'s own note on the
 * point.
 *
 * `Add to shelf` is the one row that does not call [onDismissRequest] on its own: it hands
 * off to whatever the caller opens next (a shelf sheet, most often), which has to stay open
 * after this menu's own dropdown closes. [expanded] is how a caller keeps the menu's state
 * alive underneath that -- see [PublicationActionMenuTarget].
 *
 * @param onOpen the action the cell's own tap already performs on this surface -- a resume
 *   on the continue-reading row, the publication's page everywhere else. `library-browsing`
 *   still asks for the row because a menu reached without ever tapping the cover is the one
 *   place a reader with a screen reader meets it.
 * @param onShowDetails always the publication's own page, whatever [onOpen] does here -- the
 *   two are the same action only where [onOpen] already is that page.
 */
@Composable
fun PublicationActionMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    markedFinished: Boolean,
    offersRestart: Boolean,
    downloadOffer: DownloadOffer,
    offersRemoveFromShelf: Boolean,
    onOpen: () -> Unit,
    onMark: (Boolean) -> Unit,
    onRestart: () -> Unit,
    onAddToShelf: () -> Unit,
    onDownload: () -> Unit,
    onRemoveDownload: () -> Unit,
    onRemoveFromShelf: () -> Unit,
    onShowDetails: () -> Unit,
) {
    val items = PublicationActionMenuItems.of(
        offersRestart = offersRestart,
        downloadOffer = downloadOffer,
        offersRemoveFromShelf = offersRemoveFromShelf,
    )

    DropdownMenu(expanded = expanded, onDismissRequest = onDismissRequest) {
        items.forEach { action ->
            DropdownMenuItem(
                text = { Text(stringResource(action.label(markedFinished))) },
                onClick = {
                    when (action) {
                        PublicationMenuAction.OPEN -> {
                            onDismissRequest()
                            onOpen()
                        }

                        PublicationMenuAction.MARK -> {
                            onDismissRequest()
                            onMark(!markedFinished)
                        }

                        PublicationMenuAction.RESTART -> {
                            onDismissRequest()
                            onRestart()
                        }

                        // No `onDismissRequest()` here: [expanded] going false is this
                        // row's whole job, and it is the caller's to decide when, once
                        // whatever `onAddToShelf` opens has itself closed.
                        PublicationMenuAction.ADD_TO_SHELF -> onAddToShelf()

                        PublicationMenuAction.DOWNLOAD -> {
                            onDismissRequest()
                            onDownload()
                        }

                        PublicationMenuAction.REMOVE_DOWNLOAD -> {
                            onDismissRequest()
                            onRemoveDownload()
                        }

                        PublicationMenuAction.REMOVE_FROM_SHELF -> {
                            onDismissRequest()
                            onRemoveFromShelf()
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
}

/**
 * What a cell needs to open [PublicationActionMenu], bundled so a cell's own signature grows
 * one nullable parameter rather than one per action.
 *
 * Null at a call site draws no menu at all -- the surfaces that do not yet offer one (a
 * reading-list entry the library holds no publication for, say) pass nothing rather than a
 * menu with every row disabled, which is the one shape every scenario here forbids.
 */
data class PublicationActionCallbacks(
    /** Marks a publication read or unread. The app layer owns the server round trip. */
    val onMark: (Publication, Boolean) -> Unit,
    /** Opens the confirmation `reading-progress` requires before clearing progress. */
    val onRestart: (Publication) -> Unit,
    /** The publication's own page. Defaults to the cell's own tap target. */
    val onShowDetails: ((Publication) -> Unit)? = null,
    /** Offered only where this menu opened on a shelf, a collection or a list the reader owns. */
    val onRemoveFromShelf: ((Publication) -> Unit)? = null,
    val onAddToServerList: (suspend (Publication, ServerList) -> Boolean)? = null,
)

/**
 * The trigger every view-model-holding screen wires once: a target set on long press, drawn
 * here as [PublicationActionMenu] with its three facts computed from [viewModel], and its
 * `Add to shelf` row opening [AddToShelfSheet] -- with that sheet's own download row turned
 * off through its `offersDownloadAction` flag, since this menu already offered it and a
 * reader who dismissed one must not meet it again in the next. The sheet no longer carries
 * mark, restart or show-details rows at all: this menu owns them now.
 *
 * A `remember`-ed `Publication?` rather than a bare `Boolean`, because every call site already
 * has the publication the long press was on and a second map from "is a menu open" back to
 * "which one" is a second place to drift from the first.
 */
@Composable
fun PublicationActionMenuTarget(
    target: Publication?,
    viewModel: LibraryViewModel,
    actions: PublicationActionCallbacks,
    onDismiss: () -> Unit,
    onOpen: (Publication) -> Unit,
) {
    val publication = target ?: return
    var isShelfOpen by remember(publication.id) { mutableStateOf(false) }

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

    PublicationActionMenu(
        expanded = !isShelfOpen,
        onDismissRequest = onDismiss,
        markedFinished = finished,
        offersRestart = offersRestart,
        downloadOffer = downloadOffer,
        offersRemoveFromShelf = actions.onRemoveFromShelf != null,
        onOpen = { onOpen(publication) },
        onMark = { read -> actions.onMark(publication, read) },
        onRestart = { actions.onRestart(publication) },
        onAddToShelf = { isShelfOpen = true },
        onDownload = {
            viewModel.viewModelScope.launch { viewModel.keepOffline(setOf(publication.id)) }
        },
        onRemoveDownload = { viewModel.forgetKept(setOf(publication.id)) },
        onRemoveFromShelf = { actions.onRemoveFromShelf?.invoke(publication) },
        onShowDetails = { (actions.onShowDetails ?: onOpen)(publication) },
    )

    if (isShelfOpen) {
        AddToShelfSheet(
            viewModel = viewModel,
            publications = listOf(publication),
            onDismiss = {
                isShelfOpen = false
                onDismiss()
            },
            onAddToServerList = actions.onAddToServerList,
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
