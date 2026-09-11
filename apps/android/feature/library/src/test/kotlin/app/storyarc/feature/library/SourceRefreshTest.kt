package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which one line the shelf's notice strip draws.
 *
 * `sources`' *Refresh visibility* states one refresh once, so the ranking is the
 * requirement: an incomplete shelf outranks a cached shelf, a cached shelf already says
 * "Checking for changes", a pulled refresh is spoken for by the pull indicator, and the
 * moment the sources last answered is the quietest thing left.
 *
 * The pulled case is the one worth reading twice. A pull draws `PullToRefreshBox`'s spinner
 * at the head of the shelf; a line at the foot saying the same thing is the app answering a
 * question the finger already answered.
 *
 * iOS's `SourceRefreshTests` asserts the same nine notice cases. The four pull-indicator
 * cases below have no iOS twin: SwiftUI awaits its `refreshable` closure, so there is no
 * boolean to decide.
 */
class SourceRefreshTest {

    private val cachedAt = 1_000L
    private val checkedAt = 2_000L

    private fun notice(
        refreshing: SourceRefreshOrigin? = null,
        waiting: Int = 0,
        cached: Long? = null,
        checked: Long? = null,
    ) = LibraryNotice.of(refreshing, waiting, cached, checked)

    @Test
    fun `a shelf still missing a library says so before anything else`() {
        assertEquals(
            LibraryNotice.StillBeingRead(2),
            notice(
                refreshing = SourceRefreshOrigin.AUTOMATIC,
                waiting = 2,
                cached = cachedAt,
                checked = checkedAt,
            ),
        )
    }

    @Test
    fun `a cached shelf outranks a refresh, because its own line already says checking`() {
        assertEquals(
            LibraryNotice.Cached(cachedAt),
            notice(
                refreshing = SourceRefreshOrigin.AUTOMATIC,
                cached = cachedAt,
                checked = checkedAt,
            ),
        )
    }

    @Test
    fun `a refresh nobody asked for is stated`() {
        assertEquals(
            LibraryNotice.Refreshing,
            notice(refreshing = SourceRefreshOrigin.AUTOMATIC, checked = checkedAt),
        )
    }

    @Test
    fun `a pulled refresh draws no line, because the pull indicator is already drawn`() {
        assertEquals(
            LibraryNotice.Checked(checkedAt),
            notice(refreshing = SourceRefreshOrigin.PULLED, checked = checkedAt),
        )
    }

    @Test
    fun `a pulled refresh on a shelf that never answered draws nothing at all`() {
        assertEquals(LibraryNotice.Nothing, notice(refreshing = SourceRefreshOrigin.PULLED))
    }

    @Test
    fun `when nothing is running the strip says when the sources last answered`() {
        assertEquals(LibraryNotice.Checked(checkedAt), notice(checked = checkedAt))
    }

    @Test
    fun `a library whose sources have never answered draws no indicator`() {
        assertEquals(LibraryNotice.Nothing, notice())
    }

    @Test
    fun `a cached shelf with no refresh running still says it is cached`() {
        assertEquals(LibraryNotice.Cached(cachedAt), notice(cached = cachedAt))
    }

    // The pull indicator. `sources`' *A refresh the user asked for*.

    @Test
    fun `the pull indicator follows a folder walk`() {
        assertTrue(isRefreshingShelf(LibraryScanState.Scanning(0), null))
    }

    @Test
    fun `the pull indicator follows a pull that asks a server and walks no folder`() {
        // The defect this closes. A shelf narrowed to a server walks nothing, so the
        // indicator retracted as the finger lifted and the probes ran unseen.
        assertTrue(isRefreshingShelf(LibraryScanState.Idle, SourceRefreshOrigin.PULLED))
    }

    @Test
    fun `the pull indicator does not appear for a refresh nobody pulled`() {
        // A spinner under a reader's thumb because a backoff timer fired is the app
        // interrupting them. That refresh is the notice strip's to state.
        assertFalse(isRefreshingShelf(LibraryScanState.Idle, SourceRefreshOrigin.AUTOMATIC))
    }

    @Test
    fun `the pull indicator is up for nothing at rest`() {
        assertFalse(isRefreshingShelf(LibraryScanState.Idle, null))
    }

    @Test
    fun `no source waiting is not the same as a source waiting`() {
        // The guard that keeps `waiting = 0` out of the first branch. Without it every
        // shelf would read "0 libraries are still being read".
        assertEquals(LibraryNotice.Nothing, notice(waiting = 0))
        assertEquals(LibraryNotice.StillBeingRead(1), notice(waiting = 1))
    }
}
