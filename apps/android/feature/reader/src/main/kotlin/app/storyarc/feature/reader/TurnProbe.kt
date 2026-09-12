package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalView
import app.storyarc.core.model.PageTransition
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop

/**
 * How long a run opened by a change of display position stays open.
 *
 * A bound rather than a measurement, and deliberately generous. Neither `HorizontalPager`
 * nor `AnimatedContent` reports the end of the animation it runs, and the cross-dissolve
 * runs for [FADE_MILLIS]. A window longer than the animation adds frames drawn while
 * nothing moves, and such a frame still arrives on the panel's own interval, so it raises
 * the delivered count and not the dropped one. A window shorter than the animation hides
 * the end of the turn, which is where a frame is most likely to arrive late.
 *
 * iOS's `FrameProbe.turnWindow` holds the same number for the same reason.
 */
internal const val TURN_WINDOW_MILLIS = 500L

/**
 * How long the cross-dissolve runs. `ReaderScreen` hands it to `AnimatedContent`.
 *
 * Here rather than in `ReaderScreen.kt`, and internal rather than private, because
 * [TURN_WINDOW_MILLIS] has to clear it and a test has to read both.
 */
internal const val FADE_MILLIS = 140

/**
 * How long a run opened by a change of display position stays open, or null where a change
 * of position bounds no run.
 *
 * Curl is null because the curl counts its own frames already, from the first pixel of the
 * drag to the end of the settle — see `CurledPages`. Its position moves *after* the turn, so
 * a run opened there would count the frames that follow a turn instead of the frames of one.
 *
 * Both scroll modes are null because a scroll has no discrete turn to bound a run. The spec's
 * own table says so — Scroll is "continuous scrolling, no discrete turn" — and its position
 * moves on every frame of a drag, so each move would open a run that the next move closes and
 * the numbers would describe the reader's finger.
 *
 * iOS's `PageTransition.turnWindow` states the same rule.
 */
internal val PageTransition.turnWindowMillis: Long?
    get() = when (this) {
        PageTransition.SLIDE, PageTransition.FAST_FADE -> TURN_WINDOW_MILLIS
        PageTransition.PAGE_CURL,
        PageTransition.VERTICAL_SCROLL,
        PageTransition.HORIZONTAL_SCROLL,
        -> null
    }

/**
 * Counts the frames of a turn the container animates but reports no end for.
 *
 * `page-transitions`'s *Frame budget* covers "any transition", and the instrument reached
 * the curl alone. Slide and Fast fade animate a turn too, and neither has a finger to bound
 * a run with, so the position they draw bounds it instead.
 *
 * Off unless `adb` armed it: [FrameTicker] asks [FrameProbe] on every run, and a build that
 * is not debuggable can never be armed. iOS's `View.probingTurns` is the twin.
 *
 * @param mode the transition running now. It decides whether this counts anything at all.
 * @param display reads the display position now showing. A turn is a change of it.
 *   A lambda rather than a value, so that the position is read inside [snapshotFlow] and a
 *   page turn does not recompose the caller. An instrument that costs frames measures itself.
 */
@Composable
internal fun ProbeTurns(mode: PageTransition, display: () -> Int) {
    val window = mode.turnWindowMillis ?: return
    val view = LocalView.current
    val frames = remember(view) { FrameTicker(view) }
    // A turn the reader walked out of never reaches `ended`, and a ticker nobody stopped
    // posts a frame callback for the life of the process. This is where it is stopped.
    DisposableEffect(frames) { onDispose { frames.cancel() } }
    // The effect outlives the lambda it was given: switching mode builds a fresh `Paging`,
    // and a captured reader would go on watching the position of the container that left.
    val latest by rememberUpdatedState(display)
    LaunchedEffect(frames, window) {
        // `drop(1)`: the position this composition opened on is not a turn. Without it,
        // opening a publication reports a turn that nobody made.
        snapshotFlow { latest() }.drop(1).collect {
            frames.began()
            delay(window)
            frames.ended()
        }
    }
}
