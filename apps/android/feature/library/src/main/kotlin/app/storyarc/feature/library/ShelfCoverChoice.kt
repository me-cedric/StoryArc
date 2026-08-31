package app.storyarc.feature.library

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.grid.BoundedAdaptive
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PublicationCollection

/**
 * One thing the cover picker offers.
 *
 * The composite is an option rather than an absence, because that is how a reader thinks about
 * it: a collection's cover is either "the four" or "that one", and a picker where undoing a
 * choice means finding a clear button is a picker that traps its own reader.
 */
internal sealed interface ShelfCoverOption {
    /** The four member covers, which is what a collection wears until it is told otherwise. */
    data object Composite : ShelfCoverOption

    /** One member's own cover, across the whole frame. */
    data class Member(val id: String) : ShelfCoverOption
}

/**
 * What a collection can be given for a cover, and which of them it is wearing.
 *
 * `collections-and-reading-lists`: a collection's cover "is a composite of its first four member
 * covers **unless the user sets a specific one**". [CompositeCover] has always honoured the
 * second half; nothing in either app ever let a reader reach it. This is the reaching.
 *
 * iOS's `ShelfCoverChoice` answers these cases identically.
 */
internal object ShelfCoverChoice {

    /**
     * Everything a reader may pick, in the order they are offered.
     *
     * The composite leads, always: it is the collection's own default and the way back from a
     * choice already made. The members follow in identity order -- the same order
     * [CompositeCover] reads them in, so "the first four" on the composite tile are visibly the
     * first four of the row underneath it. The library's own order was the tempting alternative
     * and moves the moment the reader touches the sort control, which [CompositeCover] refused
     * for the same reason.
     */
    fun options(collection: PublicationCollection): List<ShelfCoverOption> =
        listOf(ShelfCoverOption.Composite) +
            collection.members.sorted().map { ShelfCoverOption.Member(it) }

    /**
     * Which option the collection is wearing now.
     *
     * [CompositeCover]'s rule, word for word: the reader's choice wins, and a cover that has
     * left the collection is not the collection's cover any more. Answering it here from the
     * same premise rather than from a stored flag is what keeps the tick in the picker and the
     * artwork on the shelf from ever disagreeing.
     */
    fun chosen(collection: PublicationCollection): ShelfCoverOption {
        val member = collection.coverMemberId
        return if (member != null && member in collection.members) {
            ShelfCoverOption.Member(member)
        } else {
            ShelfCoverOption.Composite
        }
    }
}

/**
 * Choosing a collection's cover.
 *
 * A wall of the artwork itself rather than a list of titles, because the artwork is the
 * interface and this is the one screen in the app where the reader is being asked a question
 * *about* artwork. Tapping answers it and closes the sheet: there is no second confirmation for
 * a change that shows itself immediately and is undone by tapping the next one.
 *
 * iOS's `ShelfCoverPicker` is the same sheet.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun ShelfCoverPicker(
    viewModel: LibraryViewModel,
    collection: PublicationCollection,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val publications by viewModel.publications.collectAsStateWithLifecycle()
    val chosen = ShelfCoverChoice.chosen(collection)

    // The collection as it would look with no choice made, for the composite's own tile.
    // Without it the composite would preview the very cover the reader is trying to move away
    // from -- [CompositeCover] answers the chosen one when there is one, which is right
    // everywhere except on the control that offers to unchoose it.
    val unchosen = collection.copy(coverMemberId = null)

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = palette.surfaceRaised) {
        Text(
            text = stringResource(R.string.shelves_cover),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
        )
        Text(
            text = stringResource(R.string.shelves_cover_about),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
            modifier = Modifier
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(top = StoryArcSpace.hair, bottom = StoryArcSpace.md),
        )

        LazyVerticalGrid(
            // Narrower than the shelf lattice: these are single covers rather than composites
            // of four, so they stay legible small, and a collection of forty is a wall to scan
            // rather than a list to page through.
            columns = BoundedAdaptive(OPTION_MINIMUM_WIDTH, OPTION_MAXIMUM_WIDTH),
            // Bounded by what the sheet has left rather than by a height picked out of the air,
            // and not filled, so a collection of two does not leave half a sheet of nothing.
            modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
            contentPadding = PaddingValues(
                start = StoryArcSpace.gutter,
                end = StoryArcSpace.gutter,
                bottom = StoryArcSpace.gutter,
            ),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
        ) {
            items(ShelfCoverChoice.options(collection), key = { it.optionKey() }) { option ->
                val publication = (option as? ShelfCoverOption.Member)
                    ?.let { member -> publications.firstOrNull { it.id == member.id } }
                CoverOption(
                    viewModel = viewModel,
                    tiles = when (option) {
                        ShelfCoverOption.Composite -> CompositeCover.tiles(unchosen)
                        is ShelfCoverOption.Member -> listOf(option.id)
                    },
                    caption = when (option) {
                        ShelfCoverOption.Composite ->
                            stringResource(R.string.shelves_cover_composite)
                        is ShelfCoverOption.Member ->
                            publication?.displayTitle
                                ?: stringResource(R.string.shelves_list_unavailable)
                    },
                    isChosen = option == chosen,
                    // A member whose file has gone still counts as a member -- an entry the
                    // source dropped is kept rather than renumbered around -- but there is no
                    // artwork to put on a shelf, so it is shown and not offered.
                    isPickable = option == ShelfCoverOption.Composite || publication != null,
                ) {
                    viewModel.setCollectionCover(
                        (option as? ShelfCoverOption.Member)?.id,
                        collection.id,
                    )
                    onDismiss()
                }
            }
        }
    }
}

/** The narrowest a single cover in the picker still reads as one. */
private val OPTION_MINIMUM_WIDTH = 92.dp

/** And the widest, so a tablet gets more of them rather than enormous ones. */
private val OPTION_MAXIMUM_WIDTH = 140.dp

/** How thick the ring around the chosen cover is, so it reads as chosen and not as bordered. */
private val CHOSEN_RING = 3.dp

/** A stable key per option, so the grid does not rebuild a wall of covers on every choice. */
private fun ShelfCoverOption.optionKey(): String = when (this) {
    ShelfCoverOption.Composite -> "composite"
    is ShelfCoverOption.Member -> id
}

@Composable
private fun CoverOption(
    viewModel: LibraryViewModel,
    tiles: List<String>,
    caption: String,
    isChosen: Boolean,
    isPickable: Boolean,
    onPick: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = isChosen, enabled = isPickable, onClick = onPick),
    ) {
        Box {
            ShelfCover(tiles = tiles, viewModel = viewModel, width = OPTION_MAXIMUM_WIDTH)
            if (isChosen) {
                Box(
                    Modifier
                        .matchParentSize()
                        .border(
                            CHOSEN_RING,
                            palette.accent,
                            RoundedCornerShape(StoryArcRadius.sm),
                        ),
                )
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(StoryArcSpace.xs),
                )
            }
        }
        Text(
            text = caption,
            style = MaterialTheme.typography.bodySmall,
            color = if (isPickable) palette.textSecondary else palette.textTertiary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = StoryArcSpace.sm),
        )
    }
}
