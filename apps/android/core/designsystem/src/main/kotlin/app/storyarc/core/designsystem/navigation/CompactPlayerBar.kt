package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ShortNavigationBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * What is playing, resting above the navigation control.
 *
 * `audio-playback`: "a compact bar rests above the navigation control, naming the
 * publication and the chapter being spoken, and offering play, pause and a way to open the
 * full player", and it "does not displace, cover or resize the navigation control".
 *
 * **Hand-composed, and the guidance it does not follow is worth recording.** Material's
 * bottom-sheets page names *"an audio player in a music app"* as its example of a standard
 * bottom sheet, and the shipped API cannot deliver one here: `BottomSheetScaffold` has a
 * `topBar` slot and **no `bottomBar` slot**, so its peek height anchors to the window
 * bottom and this row would sit *behind* the navigation bar. The guideline is right and
 * unfollowable at material3 1.5.0-alpha26, so the row is ours and the drag-to-expand sheet
 * is deferred.
 *
 * **Two components that compile and are still wrong.** `HorizontalFloatingToolbar` needs no
 * opt-in, and `BottomAppBar` raises no deprecation warning — yet toolbars and navigation
 * bars *"should not be shown at the same time"*, and the baseline bottom app bar is *"no
 * longer recommended"*. Nothing in the build will stop either, which is why they are named
 * here.
 *
 * **Full-width `surfaceContainer`, sharing the navigation bar's own container colour**, so
 * the two read as one bottom assembly. Not iOS's inset glass capsule: Material has no
 * glass, its bottom region is full-bleed, and `ShortNavigationBar` takes no `shape` at all
 * — the capsule is not discouraged here, it is inexpressible. Copying it would import
 * iOS's visual language into a Material surface with no Material rule behind it, which is
 * what ADR-0001 exists to prevent.
 *
 * @param progress 0..1 through the current part, or null when nothing knows the duration.
 *   Null draws no line rather than an empty one — `audio-playback` allows a position with
 *   no total and forbids inventing one.
 */
@Composable
fun CompactPlayerBar(
    title: String,
    chapter: String?,
    isPlaying: Boolean,
    progress: Float?,
    labels: CompactPlayerLabels,
    onToggle: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            // The navigation bar's own container, asked of Material rather than named, so
            // the two stay one assembly through a dynamic-colour change.
            .background(ShortNavigationBarDefaults.containerColor)
            // **One element to a screen reader, with two actions.** `audio-playback`: it is
            // "announced as one element naming what is playing, with its play/pause action
            // and its open action reachable separately". `mergeDescendants` is what makes
            // the first true; the custom actions are what keep the second.
            .semantics(mergeDescendants = true) {
                customActions = listOf(
                    CustomAccessibilityAction(
                        if (isPlaying) labels.pause else labels.play,
                    ) { onToggle(); true },
                    CustomAccessibilityAction(labels.open) { onOpen(); true },
                )
            }
            .clickable(onClickLabel = labels.open, onClick = onOpen),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    // **Two lines, not one.** `audio-playback` at the largest text size:
                    // the bar "grows to fit its text rather than truncating the chapter to
                    // one word". A `Column` with no fixed height grows; the wrap is what
                    // lets it.
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                // The **chapter**, not the file. A product decision, recorded as one:
                // `01 - track.mp3` is not what a listener is in the middle of.
                chapter?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            IconButton(onClick = onToggle) {
                Icon(
                    imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (isPlaying) labels.pause else labels.play,
                    modifier = Modifier.size(24.dp),
                )
            }
        }

        // **Flat, not wavy.** Material cautions that the wavy variant "may not be as
        // visible" at small sizes and says linear indicators "shouldn't be used in any
        // elements smaller than 40dp" — this line is four.
        progress?.let {
            LinearProgressIndicator(
                progress = { it },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * What the bar's controls are called.
 *
 * Passed in rather than read from a resource, by the rule the rest of this module follows:
 * a design system that owned words would own vocabulary, and vocabulary belongs to the app.
 * The same reason [NavigationEntry.label] is a `String`.
 */
data class CompactPlayerLabels(
    val play: String,
    val pause: String,
    /** What the whole bar's action is called: "open the player". */
    val open: String,
)
