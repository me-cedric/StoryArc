package app.storyarc.core.format

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * A walk that saw nothing is two different facts, and until now it wore one face.
 *
 * `sources`' metadata cache asks for "a single unobtrusive indicator" saying the shelf is
 * cached. It must stay up when a walk saw nothing *because it could see nothing*, and leave
 * only when a walk genuinely found an empty folder -- and `ScanEvent.Finished(found, skipped)`
 * reports `0, 0` for both. A reader whose folder permission lapsed was told their library was
 * empty.
 *
 * iOS's `ScanReadabilityTests` asserts the same cases, case for case. These drive the `File`
 * walk, which is the one a host test can reach; the tree walk takes the same lambda through
 * [SafTree.childrenOrNull] and needs a `ContentResolver`, so it is asserted where one exists.
 */
class ScanReadabilityTest {

    @get:Rule
    val temporary = TemporaryFolder()

    // region The two walks that both saw nothing

    @Test
    fun `a walk over a folder that genuinely holds nothing reports no unreadable folder`() = runTest {
        val root = temporary.newFolder("empty")

        val walk = walk(root)

        assertTrue(walk.unreadable.isEmpty())
        assertEquals(listOf(ScanEvent.Finished(0, 0)), walk.events)
    }

    @Test
    fun `a walk over a folder that does not exist reports it as unreadable`() = runTest {
        // The state a restored tree lands in when the folder behind it has gone. The walk
        // finds nothing either way; only this says which nothing it was.
        val missing = File("/nowhere/at/all")

        val walk = walk(missing)

        assertEquals(listOf(missing.absolutePath), walk.unreadable)
        assertEquals(listOf(ScanEvent.Finished(0, 0)), walk.events)
    }

    @Test
    fun `a walk over a folder the app may not read reports it as unreadable`() = runTest {
        // The lapsed permission itself, which is the case task 5.1 names: the folder is
        // there, it may well be full, and the app cannot list it.
        val root = temporary.newFolder("locked")
        assumeReadableIsRefused(root)

        val walk = walk(root)

        assertEquals(listOf(root.absolutePath), walk.unreadable)
        assertEquals(listOf(ScanEvent.Finished(0, 0)), walk.events)
    }

    @Test
    fun `the finished event alone cannot tell the two apart`() = runTest {
        // The defect, stated as an assertion. Both walks end identically, so any caller
        // reading only the terminal event is deciding between an emptied library and a
        // folder it cannot see by guessing -- which is what the cached notice used to do.
        val readable = walk(temporary.newFolder("still-empty"))
        val unreadable = walk(File("/nowhere/at/all"))

        assertEquals(readable.events, unreadable.events)
        assertNotEquals(readable.unreadable, unreadable.unreadable)
    }

    // endregion

    // region A partial walk is not an empty one

    @Test
    fun `a subfolder that cannot be read makes the walk partial, not empty`() = runTest {
        // What the walk did not see is unaccounted for rather than gone, which is why this is
        // reported per directory rather than as one flag about the root. A caller that removed
        // every publication it did not meet would drop a whole series here.
        val root = temporary.newFolder("partial")
        FixtureCorpus.file("comics/single-page.cbz").copyTo(File(root, "01.cbz"))
        val locked = File(root, "Locked").also { it.mkdirs() }
        assumeReadableIsRefused(locked)

        val walk = walk(root)

        assertEquals(listOf(locked.absolutePath), walk.unreadable)
        // The root was readable, so what it did hold is still found. A partial walk is worth
        // its findings; it is only not worth trusting about what is missing.
        assertEquals(1, walk.events.filterIsInstance<ScanEvent.Found>().size)
        assertEquals(ScanEvent.Finished(1, 0), walk.events.last())
    }

    @Test
    fun `a walk that read every directory it visited reports nothing`() = runTest {
        val root = temporary.newFolder("full")
        val series = File(root, "Bone").also { it.mkdirs() }
        FixtureCorpus.file("comics/single-page.cbz").copyTo(File(series, "01.cbz"))

        val walk = walk(root)

        assertTrue(walk.unreadable.isEmpty())
        assertEquals(ScanEvent.Finished(1, 0), walk.events.last())
    }

    // endregion

    // region Driving the walk

    private data class Walk(val events: List<ScanEvent>, val unreadable: List<String>)

    /** Everything one walk reported, both channels. */
    private suspend fun walk(folder: File): Walk {
        val unreadable = mutableListOf<String>()
        val events = LibraryScanner.scan(folder) { unreadable += it }.toList()
        return Walk(events, unreadable)
    }

    /**
     * Makes a directory unlistable, and abandons the case rather than asserting nothing when
     * it cannot be.
     *
     * A process that can read a mode-0 directory -- root, or a filesystem that does not carry
     * POSIX permissions -- would make the assertions vacuous, and a vacuous test is worse than
     * none. `assumeTrue` reports the case as skipped, which is visible, rather than passing.
     */
    private fun assumeReadableIsRefused(directory: File) {
        assumeTrue("could not make $directory unreadable", directory.setReadable(false, false))
        assumeTrue("$directory is still readable", directory.listFiles() == null)
    }

    // endregion
}
