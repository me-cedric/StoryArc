package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What changed in the version just installed, shown once and then dismissed.
 *
 * **A `ModalBottomSheet`, not a full-screen dialog.** Material reserves those for a
 * multi-step task holding unsaved state, at compact widths *only*, and says to use a dialog
 * or a side sheet on a tablet instead — StoryArc runs on tablets, and this is neither
 * multi-step nor unsaved. The modal sheet's own guidance describes this content almost word
 * for word: use one *"when items require longer descriptions and icons"*. `design.md` settles
 * it, and iOS's large sheet is deliberately a different shape; [ADR-0001] is what makes that
 * allowed rather than an inconsistency.
 *
 * Capped by Material's own maximum height — it never covers the status bar — and draggable,
 * which is the component's own behaviour and is left alone. Nothing waits on it: the action
 * dismisses it, so does a drag down, so does the scrim, and so does back.
 *
 * **`skipPartiallyExpanded`, and a screenshot is why.** The first version left the partial
 * detent in place, as `design.md`'s "capped and expandable" reads at first glance. A modal
 * sheet lays its content out at the full height and is *translated* down to the partial
 * offset, so the pinned `Continue` sat below the visible edge: the emulator capture showed the
 * fourth row running off the bottom of the screen with no action anywhere. That is the one
 * thing `settings-and-about` says outright — "the dismissing action stays reachable without
 * scrolling past the content" — and no unit test can see it, because the height that hid the
 * button belongs to the dialog rather than to the content. The sheet opens expanded now, which
 * is also the shape iOS's single `.large` detent has.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun WhatsNewSheet(release: WhatsNewRelease, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        // `rememberBottomSheetState` with two values rather than the deprecated
        // `rememberModalBottomSheetState(skipPartiallyExpanded = true)`, which 1.5.0's own
        // KDoc names as the replacement. Hidden and Expanded and nothing between them.
        sheetState = rememberBottomSheetState(
            SheetValue.Hidden,
            setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        WhatsNewContent(release = release, onDismiss = onDismiss)
    }
}

/**
 * The sheet's contents, which is where every claim about it actually lives.
 *
 * Its own composable because `ModalBottomSheet` is a dialog window and a unit test cannot
 * compose one — `WhatsNewLayoutTest` composes this, in a box the size of the smallest window
 * this app supports, which is the same bound the sheet imposes.
 *
 * **The rows scroll and the action does not.** `settings-and-about` at the largest text size:
 * "the screen scrolls if it must, and the dismissing action stays reachable without scrolling
 * past the content". `weight(1f, fill = false)` is what holds it: the scrolling column takes
 * the height it needs up to whatever is left after the button, and no more.
 */
@Composable
internal fun WhatsNewContent(
    release: WhatsNewRelease,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState()),
        ) {
            Column(
                modifier = Modifier.padding(
                    start = StoryArcSpace.gutter,
                    end = StoryArcSpace.gutter,
                    bottom = StoryArcSpace.md,
                ),
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
            ) {
                Text(
                    text = stringResource(R.string.whats_new_title),
                    style = MaterialTheme.typography.headlineMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(R.string.whats_new_version, release.version),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            }
            WhatsNewNotes(release.notes)
        }

        Button(
            onClick = onDismiss,
            modifier = Modifier
                .fillMaxWidth()
                .padding(StoryArcSpace.gutter),
        ) {
            Text(stringResource(R.string.whats_new_continue))
        }
    }
}

/**
 * The same rows, every release of them, reached from About.
 *
 * `settings-and-about`: what changed "is reachable from the About screen, along with the
 * entries for earlier versions", **and** "reaching it that way does not change what the app
 * considers seen". The second half is why this takes a list of releases and nothing else:
 * there is no store here to write to.
 *
 * No scroll of its own, and no `Continue`. `SettingsScreen` already scrolls every group, and
 * a second vertical scroll inside the first is measured with an infinite height — which threw
 * and took the whole app down every time anyone opened About, which is why `AboutGroup` says
 * the same thing at the same length.
 */
@Composable
internal fun WhatsNewHistory(
    releases: List<WhatsNewRelease>,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        OutlinedButton(onClick = onBack) { Text(stringResource(R.string.settings_back)) }
        Text(
            text = stringResource(R.string.whats_new_title),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        for (release in releases) {
            Text(
                text = stringResource(R.string.whats_new_version, release.version),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
                modifier = Modifier.padding(top = StoryArcSpace.sm),
            )
            WhatsNewNotes(release.notes)
        }
    }
}

/** One release's rows, so the sheet and the About screen cannot draw them differently. */
@Composable
private fun WhatsNewNotes(notes: List<WhatsNewNote>) {
    val palette = LocalStoryArcPalette.current

    for (note in notes) {
        ListItem(
            supportingContent = {
                Text(
                    text = stringResource(note.body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            },
            leadingContent = {
                // **A fixed column, in dp, which is the point of it.** Material asks for 200%
                // text support and, in the same breath, says not to resize a component that
                // contains no text — and an icon contains none. Left to scale, it takes a
                // third of a 320 dp line at 200% and the sentence beside it is measured into
                // what is left. `WhatsNewLayoutTest` is what holds this, by measuring where
                // the sentence starts at both text sizes.
                //
                // A `Box` around the `Icon` rather than a size on the `Icon` itself: the
                // alignment is what keeps a short icon centred in the column beside a
                // sentence that has grown to four lines.
                Box(
                    modifier = Modifier.size(ICON_COLUMN),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = note.icon,
                        // Decorative. The heading beside it says the same thing in words, and
                        // a screen reader announcing both would say everything twice.
                        contentDescription = null,
                        tint = palette.accent,
                        modifier = Modifier.size(ICON),
                    )
                }
            },
            // Transparent, because the sheet's own container is the surface here and a
            // second one behind every row draws a card the design does not have.
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        ) {
            Text(
                text = stringResource(note.title),
                style = MaterialTheme.typography.titleSmall,
                color = palette.textPrimary,
            )
        }
    }
}

/** The width the icons sit in, whatever the reader's text size. */
private val ICON_COLUMN = 40.dp

/** The icon inside it. */
private val ICON = 28.dp
