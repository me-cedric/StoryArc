package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What the library says about the publications it could not open.
 *
 * **This replaces one `Text` in the screen's `bottomBar`**, which read
 * `library_skipped` — a bare count, and the reasons the scanner had already produced were
 * dropped on the way. `library-browsing`'s *What could not be opened* asks for the
 * publication's name where there is one, the reasons where there are several, no timer, and
 * a way back to the list after a dismissal. A count in a bar answered none of it.
 *
 * **No timer here, and nowhere for one to live.** What is shown is a function of
 * [SkippedPublications.notice], which the view model holds, so a recomposition cannot lose
 * it and a reader who dismissed it cannot have it come back. The only local state is whether
 * the list is open. iOS's `ScanSummary` did have a six-second countdown; Android's count
 * never did, which `design.md` gets wrong for this platform — the timer is an iOS-only
 * removal and the rest of this is both.
 *
 * **Inline above the shelf rather than in the `bottomBar`.** The bar version did not obscure
 * a cover — Compose insets the content above it — but it sat below the shelf, away from the
 * scan it was about, on every one of the screen's surfaces. `library-browsing` wants a notice
 * a reader can act on, and an action at the foot of a long grid is one nobody meets.
 *
 * iOS draws the same three states from `SkippedNotice`.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun SkippedNotice(
    skipped: SkippedPublications,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isListShown by remember { mutableStateOf(false) }

    when (val notice = skipped.notice) {
        SkippedPublications.Notice.Nothing -> Unit

        is SkippedPublications.Notice.One -> SkippedBanner(
            sentence = stringResource(R.string.library_skipped_one, notice.name),
            reason = notice.reason,
            onOpenList = { isListShown = true },
            onDismiss = onDismiss,
            modifier = modifier,
        )

        is SkippedPublications.Notice.Several -> SkippedBanner(
            sentence = stringResource(R.string.library_skipped, notice.count),
            reason = null,
            onOpenList = { isListShown = true },
            onDismiss = onDismiss,
            modifier = modifier,
        )

        // Dismissed, and the way back. `library-browsing`: "the list remains reachable from
        // the library, so a reader who dismissed it in the middle of something can come back
        // to it" — and "the count is not shown again for the same publications", which is why
        // this one carries no number.
        SkippedPublications.Notice.Reachable -> Row(
            modifier = modifier.fillMaxWidth().padding(horizontal = StoryArcSpace.xs),
        ) {
            OpenSkippedList(onClick = { isListShown = true })
        }
    }

    if (isListShown) {
        ModalBottomSheet(
            onDismissRequest = { isListShown = false },
            // Hidden and Expanded and nothing between them, like `WhatsNewSheet`: a modal
            // sheet lays its content out at full height and is translated down to a partial
            // detent, which puts the last rows below the visible edge.
            sheetState = rememberBottomSheetState(
                SheetValue.Hidden,
                setOf(SheetValue.Hidden, SheetValue.Expanded),
            ),
        ) {
            SkippedList(entries = skipped.entries)
        }
    }
}

/**
 * The notice itself: what happened, and the two things a reader can do about it.
 *
 * Its own composable because the sheet above is a dialog window that a unit test cannot
 * compose — `SkippedNoticeTest` composes this and the list directly, which is the same split
 * `WhatsNewSheet` uses and for the same reason.
 */
@Composable
internal fun SkippedBanner(
    sentence: String,
    reason: String?,
    onOpenList: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    // The controls sit **under** the sentence rather than beside it. A row measures its
    // unweighted children first, so a column of two labelled buttons beside a weighted
    // sentence can take the whole width and leave the sentence none — which is what the
    // first version of this did, and `SkippedNoticeTest` caught it as a node that existed
    // and was not displayed. Stacking also survives the largest text size, which AGENTS.md
    // §6 asks for a capture of.
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Column(
            // One node for a screen reader rather than two, so the notice is announced once
            // and says both halves. `library-browsing`: "it is announced once, naming the
            // publication where there is one and the count where there are several".
            //
            // Merged rather than replaced by a `contentDescription`: a description would be
            // the same two sentences written a second time, and the day one of them changed
            // the spoken version would keep the old wording. The buttons are outside this
            // column, so the merge does not swallow either of them.
            modifier = Modifier.semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
        ) {
            Text(
                text = sentence,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            // Verbatim from `publication-formats`. Shown here only when there is one
            // publication to attribute it to; several reasons belong in the list, where each
            // sits beside its own name.
            if (reason != null) {
                Text(
                    text = reason,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
            OpenSkippedList(onClick = onOpenList)
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.library_skipped_dismiss))
            }
        }
    }
}

/**
 * The way to the list, and it is a control with a name.
 *
 * `library-browsing`: "the way to the list is a control with a name, not the whole notice".
 * Nothing in the banner carries a click, which is what makes that true rather than merely
 * stated — a row that is itself clickable is announced as a button, and a reader reaching for
 * the dismissal opens a sheet instead.
 */
@Composable
private fun OpenSkippedList(onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Text(stringResource(R.string.library_skipped_list))
    }
}

/**
 * Every publication the library could not open, each with its own reason.
 *
 * `library-browsing`: the notice "leads to a list naming each with its own reason", and "the
 * reasons are not merged: two files that failed differently say different things". A list is
 * what makes that visible — the banner above it can carry one sentence, and the count was
 * what carrying none looked like.
 */
@Composable
internal fun SkippedList(
    entries: List<SkippedPublications.Entry>,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        item {
            Text(
                text = stringResource(R.string.library_skipped_list),
                style = MaterialTheme.typography.headlineSmall,
                color = palette.textPrimary,
            )
        }
        items(entries, key = { it.name }) { entry ->
            Column(
                // One stop per publication, naming it and saying why. Two would make a reader
                // swipe twice per row to learn one fact.
                modifier = Modifier.semantics(mergeDescendants = true) {},
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
            ) {
                Text(
                    text = entry.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = palette.textPrimary,
                )
                Text(
                    text = entry.reason,
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            }
        }
    }
}
