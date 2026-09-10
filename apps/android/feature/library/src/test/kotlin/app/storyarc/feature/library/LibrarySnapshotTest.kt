package app.storyarc.feature.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When last session's shelf is replaced, and when it is left alone.
 *
 * Both refusals are about a reader's next launch. `sources` asks the cached catalogue to
 * make the library "open instantly and stay browsable while offline" — and a cache that
 * overwrites itself with the results of a failed walk delivers the opposite: an empty
 * shelf, dated now.
 */
class LibrarySnapshotTest {

    @Test
    fun `a finished walk that found something is written`() {
        assertTrue(LibrarySnapshot.worthWriting(partial = false, shelf = 12, cached = 8))
    }

    @Test
    fun `a partial walk is never written, because it has refreshed nothing`() {
        // The indicator states when the shelf was last refreshed. A walk that could not
        // list a directory has refreshed nothing, and writing `now` puts that on disk for
        // the next launch too.
        assertFalse(LibrarySnapshot.worthWriting(partial = true, shelf = 12, cached = 8))
        assertFalse(LibrarySnapshot.worthWriting(partial = true, shelf = 12, cached = 0))
    }

    @Test
    fun `an empty shelf does not replace a snapshot that holds something`() {
        // One unreachable server, or one folder the system stopped granting, would
        // otherwise cost the reader their whole cached library on the next launch.
        assertFalse(LibrarySnapshot.worthWriting(partial = false, shelf = 0, cached = 8))
    }

    @Test
    fun `an empty shelf with nothing cached is written, because there is nothing to lose`() {
        // A library that really is empty. Writing it is what lets the "no publications yet"
        // state survive a restart instead of flickering through a stale shelf.
        assertTrue(LibrarySnapshot.worthWriting(partial = false, shelf = 0, cached = 0))
    }
}
