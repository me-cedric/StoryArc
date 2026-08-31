package app.storyarc

import android.graphics.Bitmap
import android.text.format.Formatter
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.cover.CoverlessWell
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.ImportedCopies

/** The proportions of a comic cover, near enough for every publisher. */
private const val COVER_ASPECT = 2f / 3f

/**
 * What the cover is decoded at, rather than the drawn width.
 *
 * The cell is sized by the grid, and a decode keyed on a measured width would be re-run on
 * every reflow — a rotation would re-inflate every archive on the shelf.
 */
private const val COVER_PIXELS = 512

/**
 * One publication on this device, drawn as the library draws it.
 *
 * The artwork is the interface, so removal is a long press rather than a control on every
 * cell: a delete glyph on each cover is chrome competing with the thing it sits on, and this
 * screen is read far more often than it is pruned.
 *
 * Its own cell rather than `feature/library`'s, for the same reason [HomeDestination]'s is:
 * the library's `CoverGrid` is internal to that module and carries a selection model, a
 * match-group layout and a bulk-action path that none of them belong here. The three rules
 * that matter are held here as they are held there — a 4 dp radius because a comic cover is
 * printed stock, letterboxing onto `surfaceSunken` rather than cropping the artwork, and the
 * well that stands in for artwork that does not exist.
 *
 * The first two are `design.md`'s and were copied. The third could not be: it was written
 * inside `CoverGrid`'s private cell, so this file simply did without it and drew an empty
 * box. It is `:core:designsystem`'s `CoverlessWell` now, and this cell asks — the same move,
 * and the same reason, as `rememberCoverColumns`.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun OnDeviceCover(
    publication: Publication,
    /**
     * Where the artwork comes from, as a function rather than as the view model that holds it.
     *
     * `:feature:library`'s `HomeCoverArt` — the cell this one is deliberately the twin of —
     * already takes its cover this way, and the reason applies here with more force: the
     * branch that matters is the one taken when this answers `null`, and that is a state a
     * test can hand over in one line while a `LibraryViewModel` is an `AndroidViewModel` a
     * test would have to construct. This cell reads nothing else off the model, so nothing
     * else is worth carrying. `DownloadsCoverlessWellTest` is what the change buys.
     */
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpen: () -> Unit,
    /** Null when this is not something the app put here, and so not its to delete. */
    onRemove: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current
    var artwork by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    var isOffering by remember(publication.id) { mutableStateOf(false) }
    LaunchedEffect(publication.id) { artwork = cover(publication, COVER_PIXELS) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onOpen,
                onLongClick = { if (onRemove != null) isOffering = true },
            ),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(COVER_ASPECT)
                .clip(RoundedCornerShape(StoryArcRadius.cover))
                .background(palette.surfaceSunken),
            contentAlignment = Alignment.Center,
        ) {
            val art = artwork
            if (art != null) {
                Image(
                    bitmap = art.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // The third rule this cell holds as the library holds it, and the one it
                // was missing. There was no else branch here at all, so a publication with
                // no artwork was a bare `surfaceSunken` rectangle — on a shelf whose own
                // requirement, `offline-downloads`' "Everything on this device", asks for
                // "the same grid, the same cells" as the library. A cell that says nothing
                // about the book it stands for is not the same cell.
                //
                // With the format, because the library's cell names it and this cell is
                // meant to be that cell: `no-pages` reads `no-pages` / `CBZ` here exactly
                // as it does one destination away.
                //
                // Drawn only. The `combinedClickable` above merges this whole cell into one
                // spoken node, and the caption at the foot of the column is what states the
                // title to TalkBack — so the well is silent, which `CoverlessWell` does for
                // every caller rather than leaving each to remember. Without that this cell
                // announced `Foreign Codec, CBZ, Foreign Codec`.
                CoverlessWell(
                    title = publication.displayTitle,
                    format = publication.format.displayName,
                )
            }

            DropdownMenu(expanded = isOffering, onDismissRequest = { isOffering = false }) {
                DropdownMenuItem(
                    text = {
                        Text(
                            stringResource(
                                R.string.downloads_remove_action,
                                publication.displayTitle,
                            ),
                        )
                    },
                    onClick = {
                        isOffering = false
                        onRemove?.invoke()
                    },
                )
            }
        }
        Text(
            text = publication.displayTitle,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * One transfer: what it is, where it has got to, and the two things a reader can do to it.
 *
 * Deliberately not a cover. A transfer is not a book yet — it has no artwork on this device
 * to draw — and giving it a cell the size of a finished publication is how a downloads
 * screen turns back into the queue inspector this destination exists to stop being.
 *
 * **Stop and reorder, and not yet pause.** Those two are what the app can honestly offer
 * from here: the order and the record are the download store's, and this writes them. Pause
 * and resume belong to the running `DownloadQueue`, which lives with the browser that
 * started the transfer — a button here would write "paused" into the record while the bytes
 * kept arriving. A control that lies is worse than one that is missing.
 */
@Composable
internal fun DownloadQueueRow(
    download: Download,
    canReorder: Boolean,
    onReorder: (Boolean) -> Unit,
    onStop: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    // At the accessibility font scales the title and its three controls cannot share a
    // line: the title is squeezed to a couple of characters while *Stop* takes half the
    // row. Above the threshold the row becomes two. iOS makes the same split at
    // `dynamicTypeSize.isAccessibilitySize`.
    val isStacked = LocalDensity.current.fontScale >= 1.5f

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(StoryArcRadius.md))
            .background(palette.surfaceRaised)
            .padding(StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        val title = @Composable { modifier: Modifier ->
            Text(
                text = download.title,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
                maxLines = if (isStacked) 3 else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = modifier,
            )
        }
        val controls = @Composable {
            if (canReorder) {
                IconButton(onClick = { onReorder(false) }) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowUp,
                        contentDescription = stringResource(
                            R.string.downloads_move_earlier,
                            download.title,
                        ),
                        tint = palette.textSecondary,
                    )
                }
                IconButton(onClick = { onReorder(true) }) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(
                            R.string.downloads_move_later,
                            download.title,
                        ),
                        tint = palette.textSecondary,
                    )
                }
            }
            TextButton(onClick = onStop) { Text(stringResource(R.string.downloads_stop)) }
        }

        if (isStacked) {
            title(Modifier.fillMaxWidth())
            Row(verticalAlignment = Alignment.CenterVertically) { controls() }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                title(Modifier.weight(1f))
                controls()
            }
        }

        when (val state = download.state) {
            // The reason, in the reader's words, and how many times it was tried.
            // `offline-downloads` requires "a plain-language reason and a retry action"; the
            // retry belongs to the running queue, which is why the count is shown rather
            // than hidden behind a button that cannot reach it.
            is Download.State.Failed -> Text(
                text = pluralStringResource(
                    R.plurals.downloads_failed,
                    state.attempts,
                    state.reason,
                    state.attempts,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
            is Download.State.Paused -> Text(
                text = stringResource(state.reason.explanationRes),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
            else -> {
                val fraction = download.fraction
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    // No size from the server, so no bar that could be honest about a
                    // fraction. `offline-downloads` would rather show an indeterminate state
                    // than a fabricated total.
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

/**
 * Confirmed, because it deletes bytes.
 *
 * `offline-downloads` says the app "never deletes a download without asking", and although
 * that sentence is about the low-storage case, a reader's own long press deserves the same
 * courtesy.
 */
@Composable
internal fun RemoveDownloadDialog(
    download: Download,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.downloads_remove_title)) },
        text = {
            // `local-library` asks for more of this sentence than a download needs. Deleting
            // an imported copy "confirms, naming the title and the space to be freed, and
            // states that the original file elsewhere is untouched" — the last clause
            // because an import is the one row here with an original somewhere, and a reader
            // must not have to guess whether the app is about to reach outside itself.
            Text(
                if (ImportedCopies.isImported(download)) {
                    stringResource(
                        R.string.downloads_remove_body_imported,
                        download.title,
                        Formatter.formatShortFileSize(context, download.downloadedBytes),
                    )
                } else {
                    stringResource(R.string.downloads_remove_body, download.title)
                },
            )
        },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.downloads_remove)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.downloads_cancel)) }
        },
    )
}

/** Why this one is not moving, in the reader's terms. */
private val Download.Pause.explanationRes: Int
    get() = when (this) {
        Download.Pause.BY_READER -> R.string.downloads_paused_by_reader
        Download.Pause.WAITING_FOR_WIFI -> R.string.downloads_paused_waiting_for_wifi
        Download.Pause.OUT_OF_SPACE -> R.string.downloads_paused_out_of_space
    }
