package app.storyarc.feature.library

import android.text.format.DateUtils
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * Who started the refresh that is running now.
 *
 * `sources`' *Refresh visibility* states one refresh once: a surface whose own gesture
 * already draws an indicator does not draw a second one. A pull draws [PullToRefreshBox]'s
 * own spinner, so the only refresh the shelf's notice strip has to speak for is the one
 * nobody pulled — the library appearing, a source being added, the retry schedule,
 * connectivity regained, and the app returning to the foreground.
 *
 * This platform needed the distinction first. [ShelfRefresh] records that the pull indicator
 * follows the folder walk alone, so a pull on a shelf narrowed to a server retracts as the
 * finger lifts and the probes run unseen, and it names the fix: *"a signal that tells a pull
 * from the backoff loop"*. This is that signal, and it closes that cost as well.
 *
 * iOS's `SourceRefreshOrigin` is the twin.
 */
enum class SourceRefreshOrigin {
    /** The reader pulled. The platform's spinner is this refresh's indicator. */
    PULLED,

    /** Nobody asked. The strip is this refresh's indicator. */
    AUTOMATIC,
}

/**
 * What the shelf's notice strip says about its sources, and in what order.
 *
 * Four things can be true at once and exactly one line is drawn, which makes this a decision
 * rather than a layout. Pure, and its own type, for the reason [ShelfRefresh] is: a decision
 * written inside a composable is a decision nothing can assert. iOS's `LibraryNotice` holds
 * the same five branches in the same order.
 */
sealed interface LibraryNotice {
    /** A source is still being read and has put nothing on the shelf yet. */
    data class StillBeingRead(val waiting: Int) : LibraryNotice

    /** The shelf is last session's. That line already says "Checking for changes". */
    data class Cached(val atEpochMillis: Long) : LibraryNotice

    /** A refresh nobody asked for is running. */
    data object Refreshing : LibraryNotice

    /** When the sources last answered. */
    data class Checked(val atEpochMillis: Long) : LibraryNotice

    /** Nothing worth saying. */
    data object Nothing : LibraryNotice

    companion object {
        /**
         * Which line the strip draws.
         *
         * The order is the ranking, and each step earns its place:
         *
         * 1. **A shelf that is incomplete** outranks everything. [sourcesStillBeingRead]
         *    counts a source that is `Connecting` *and* has contributed nothing, which is
         *    the silence after a server is added.
         * 2. **A shelf that is last session's** comes next, and it is why there is no
         *    double-statement here: `library_cached` already reads "Showing what was here
         *    … Checking for changes", so a refreshing line above it would say the second
         *    half twice.
         * 3. **A refresh nobody pulled.** Not a pulled one — see [SourceRefreshOrigin].
         * 4. **When the sources last answered.** The quietest thing the strip has to say,
         *    and the one that answers "did it work" at any moment rather than for three
         *    seconds after. `sources` asks the indicator to state "when it was last
         *    refreshed"; until this line that was true only for a shelf that was offline.
         * 5. **Nothing.** A library with no moment to report draws no indicator here, per
         *    *Nothing to say*. That is a statement about *timing* only: a source that was
         *    asked and never answered is named at the foot of the shelf instead, by
         *    [sourcesNeverReached] and [NeverReachedNotice], because `library-browsing` asks
         *    the library to name it rather than to stay quiet about it.
         */
        fun of(
            refreshing: SourceRefreshOrigin?,
            waiting: Int,
            cachedAtEpochMillis: Long?,
            checkedAtEpochMillis: Long?,
        ): LibraryNotice = when {
            waiting > 0 -> StillBeingRead(waiting)
            cachedAtEpochMillis != null -> Cached(cachedAtEpochMillis)
            refreshing == SourceRefreshOrigin.AUTOMATIC -> Refreshing
            checkedAtEpochMillis != null -> Checked(checkedAtEpochMillis)
            else -> Nothing
        }
    }
}

/**
 * Whether the pull indicator stays down.
 *
 * `sources`' *A refresh the user asked for*: the pull indicator runs for as long as the
 * refresh runs, **including a refresh that asks only a remote source and walks no folder**.
 * This used to read the scan alone, so a pull on a shelf narrowed to a server retracted as
 * the finger lifted and the probes ran unseen — the cost [ShelfRefresh] records.
 *
 * A refresh nobody pulled does not hold it down. That one is the strip's to state, and a
 * spinner appearing under a reader's thumb because a backoff timer fired is the app
 * interrupting them.
 *
 * **This function has no iOS twin, and the asymmetry is real rather than an omission.**
 * SwiftUI awaits its `refreshable` closure, so the spinner already follows whatever that
 * closure does; there is no boolean to decide. ADR-0001 asks for the same shape where the
 * platforms have the same problem, and here they do not.
 */
internal fun isRefreshingShelf(
    scan: LibraryScanState,
    refreshing: SourceRefreshOrigin?,
): Boolean = scan is LibraryScanState.Scanning || refreshing == SourceRefreshOrigin.PULLED

/**
 * The line that says a refresh nobody asked for is running.
 *
 * Drawn like [CachedNotice] and [StillBeingReadNotice], because it takes their place in the
 * same strip and a reader should not be able to tell that three composables are involved.
 *
 * A polite live region, so TalkBack states the change rather than leaving a reader to find a
 * line that appeared behind them. Polite rather than assertive: a refresh is not urgent, and
 * `sources`' *Automatic recovery* forbids interrupting anyone.
 *
 * No source is named and no count is given. `sources`' non-goals say why the count is absent:
 * a server answers in one request and a folder walk answers in thousands, and those are not
 * the same unit.
 */
@Composable
internal fun RefreshingNotice(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(R.string.library_refreshing),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = modifier
            .fillMaxWidth()
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}

/**
 * The line that says when the sources last answered.
 *
 * The platform's own phrasing for "twelve minutes ago", which `localization` requires rather
 * than a string this app assembles and then has to translate four times — the same call
 * [CachedNotice] makes. It is read at the moment it is drawn, so it is right whenever the
 * strip is laid out again. It does not tick on its own and does not need to: a line that is
 * one recomposition behind still answers the question a line that vanished cannot answer at
 * all.
 */
/**
 * How recent counts as "just now".
 *
 * Five seconds rather than one: the line is drawn when the shelf is laid out, not on a
 * ticker, so a one-second window would be missed by the very redraw that follows a refresh.
 * iOS's `justNow` is the same number.
 */
private const val JUST_NOW_MILLIS = 5_000L

@Composable
internal fun CheckedNotice(checkedAtEpochMillis: Long, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    // **Zero of a unit is never good copy, and this line met a reader at zero.** It read
    // "Libraries checked 0 minutes ago." on an emulator on 2026-09-11, because
    // `MINUTE_IN_MILLIS` as the minimum resolution reads every duration under a minute as
    // zero of them -- and the moment right after a refresh is exactly when a reader looks,
    // because they just asked for one. `SECOND_IN_MILLIS` moved it to "0 seconds ago", which
    // is the same fault one unit down.
    //
    // So the first seconds get a sentence of their own, and everything after them gets the
    // platform's own phrasing, which `localization` requires rather than a duration this app
    // assembles and then has to translate four times. iOS has the same two branches, for the
    // same reason: its `.relative(presentation: .named)` says "now" at zero, which composes
    // as "Libraries checked now."
    val elapsed = System.currentTimeMillis() - checkedAtEpochMillis
    val text = if (elapsed < JUST_NOW_MILLIS) {
        stringResource(R.string.library_checked_now)
    } else {
        stringResource(
            R.string.library_checked,
            DateUtils.getRelativeTimeSpanString(
                checkedAtEpochMillis,
                System.currentTimeMillis(),
                DateUtils.SECOND_IN_MILLIS,
            ).toString(),
        )
    }

    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = modifier
            .fillMaxWidth()
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}
