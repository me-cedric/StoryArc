package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.control.MIN_TOUCH_TARGET
import app.storyarc.core.designsystem.feedback.StoryArcFeedback
import app.storyarc.core.designsystem.feedback.rememberHaptics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlin.math.roundToInt

/**
 * How much of the shelf's width the rail takes, which is its hit region: 48 dp, Material's
 * least touch target.
 *
 * Stated rather than measured, because the shelf has to reserve it *before* the rail is laid
 * out: the rail floats over the grid at [Alignment.CenterEnd], so a shelf that did not inset
 * itself drew its last column underneath it. It did -- the third cover and its title were cut
 * off down the right edge of every frame taken on 2026-09-11.
 */
internal val RAIL_WIDTH: Dp = MIN_TOUCH_TARGET

/** The padding above the first letter and below the last, inside the hit region. */
private val RAIL_INSET: Dp = StoryArcSpace.sm

private val CAPSULE_WIDTH: Dp = LibraryRail.ENTRY_HEIGHT + StoryArcSpace.xs * 2

private val BUBBLE_SIZE: Dp = 56.dp

/**
 * The index itself, down the trailing edge of the shelf: **one scrubber**.
 *
 * `close-the-audited-gaps` 24.6, decision O23. The rail used to be twenty-seven buttons of 24 dp
 * with no gap between them. It is one hit region now, [RAIL_WIDTH] wide and as tall as the
 * letters: a tap or a drag along it chooses the letter under the finger, ticks once for each new
 * letter, and names the letter in a bubble beside the finger. Every letter stays drawn while the
 * space allows ([LibraryRail.collapsed]), and [RailScrub] reads the finger against all of them
 * regardless.
 *
 * `library-browsing`'s *The index without sight* is why the semantics are what they are:
 *
 * - the rail is one node named *Alphabetical index*, announced once, with the letter last chosen
 *   as its state,
 * - it is a **value picker** over the letters, with a range and steps like a slider:
 *   TalkBack's swipe up and down steps to the next and the previous letter, which is the
 *   step-by-step control the scrub has instead of buttons,
 * - and every letter is also a named *Jump to X* action, for a reader who knows the one they
 *   want.
 *
 * Nothing here is the only statement of anything: the shelf's own section headings say the same
 * thing in the content. iOS's `IndexRail` is the twin.
 */
@Composable
internal fun IndexRail(
    entries: List<RailEntry>,
    onChoose: (RailEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (entries.isEmpty()) return
    val palette = LocalStoryArcPalette.current
    val haptics = rememberHaptics()
    // Read before the modifier rather than inside it: a `semantics` block is not a composable
    // scope, so a `stringResource` call in there does not compile.
    val railName = stringResource(R.string.library_index)
    val jumps = entries.map { stringResource(R.string.library_index_jump, it.label) }
    val choose by rememberUpdatedState(onChoose)
    var chosen by remember(entries) { mutableIntStateOf(-1) }
    var touching by remember(entries) { mutableIntStateOf(-1) }
    var bubbleTop by remember { mutableFloatStateOf(0f) }
    val density = LocalDensity.current
    val insetPx = with(density) { RAIL_INSET.toPx() }
    val bubblePx = with(density) { BUBBLE_SIZE.toPx() }
    val bubbleGapPx = with(density) { ((RAIL_WIDTH - CAPSULE_WIDTH) / 2 + StoryArcSpace.sm).toPx() }

    BoxWithConstraints(modifier.fillMaxHeight()) {
        val shown = LibraryRail.collapsed(entries, maxHeight - RAIL_INSET * 2)
        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(RAIL_WIDTH)
                .pointerInput(entries) {
                    awaitEachGesture {
                        var last = -1
                        fun move(y: Float) {
                            val index = RailScrub.index(y, size.height.toFloat(), insetPx, entries.size)
                                ?.takeIf { it != last }
                                ?: return
                            last = index
                            touching = index
                            chosen = index
                            bubbleTop = (y - bubblePx / 2).coerceIn(0f, maxOf(0f, size.height - bubblePx))
                            haptics.play(StoryArcFeedback.SELECTION)
                            choose(entries[index])
                        }
                        val down = awaitFirstDown()
                        down.consume()
                        move(down.position.y)
                        do {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            move(change.position.y)
                            change.consume()
                        } while (change.pressed)
                        touching = -1
                    }
                }
                .clearAndSetSemantics {
                    contentDescription = railName
                    role = Role.ValuePicker
                    stateDescription = entries.getOrNull(chosen)?.label.orEmpty()
                    progressBarRangeInfo = ProgressBarRangeInfo(
                        current = chosen.coerceAtLeast(0).toFloat(),
                        range = 0f..(entries.size - 1).toFloat(),
                        steps = (entries.size - 2).coerceAtLeast(0),
                    )
                    setProgress { value ->
                        val index = value.roundToInt().coerceIn(0, entries.size - 1)
                        chosen = index
                        choose(entries[index])
                        true
                    }
                    customActions = entries.mapIndexed { index, entry ->
                        CustomAccessibilityAction(jumps[index]) {
                            chosen = index
                            choose(entry)
                            true
                        }
                    }
                },
        ) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .width(CAPSULE_WIDTH)
                    .background(palette.surfaceOverlay, CircleShape)
                    .padding(vertical = RAIL_INSET),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                shown.forEach { entry ->
                    Box(Modifier.size(LibraryRail.ENTRY_HEIGHT), contentAlignment = Alignment.Center) {
                        Text(
                            text = entry.label,
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.textSecondary,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            entries.getOrNull(touching)?.let { entry ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset { IntOffset(-(bubblePx + bubbleGapPx).roundToInt(), bubbleTop.roundToInt()) }
                        .requiredSize(BUBBLE_SIZE)
                        .background(palette.surfaceOverlay, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = entry.label,
                        style = MaterialTheme.typography.headlineMedium,
                        color = palette.textPrimary,
                    )
                }
            }
        }
    }
}
