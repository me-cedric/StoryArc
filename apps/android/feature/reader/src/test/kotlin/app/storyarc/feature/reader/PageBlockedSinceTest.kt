package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * [ReaderViewModel.pageBlockedSince] -- what `NetworkNotice` counts from -- and `warm`'s own
 * reset of the trouble a page turn leaves behind.
 *
 * The rule the timing defect turned on: a failure's own clock, once one exists, must win
 * over the plainer "still waiting on the first read" clock, and a turn away forgets the
 * page being left rather than carrying its trouble onto the one turned to. iOS's
 * `PageBlockedSinceTests` and `ReaderModelTests.turningResetsPageTrouble` are the same two
 * rules.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PageBlockedSinceTest {

    private fun model() = ReaderViewModel(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/comics/one.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "One",
            origin = MetadataOrigin.INFERRED,
        ),
        resolver = RuntimeEnvironment.getApplication().contentResolver,
        path = "/comics/one.cbz",
    )

    @Test
    fun `neither set means no trouble`() {
        assertNull(model().pageBlockedSince)
    }

    @Test
    fun `only waiting on the first read counts from that`() {
        val reader = model()
        reader.pageWaitStarted = 1_000L
        assertEquals(1_000L, reader.pageBlockedSince)
    }

    @Test
    fun `a failure's own clock wins over waiting once one exists`() {
        val reader = model()
        reader.pageWaitStarted = 5_000L
        reader.pageFailingSince = 1_000L
        assertEquals(1_000L, reader.pageBlockedSince)
    }

    @Test
    fun `turning the page forgets the trouble the page being left had`() = runBlocking {
        val reader = model()
        reader.pageWaitStarted = 1_000L
        reader.pageFailingSince = 1_000L

        // `pages.value` is empty in this fixture, so `warm`'s own decode loop finds
        // nothing to read -- what is under test is only the reset a genuine index change
        // triggers, which does not depend on a publication actually being open.
        reader.warm(6)

        assertNull(reader.pageWaitStarted)
        assertNull(reader.pageFailingSince)
    }

    @Test
    fun `warming the same index again does not wipe a failure still going on`() = runBlocking {
        // `noteMemoryPressure` re-warms the current index, and must not read as a page
        // turn -- otherwise a narrowing prefetch window would restart the 60s clock on
        // the very page it is still failing against.
        val reader = model()
        assertEquals(0, reader.currentIndex)
        reader.pageFailingSince = 1_000L

        reader.warm(0)

        assertEquals(1_000L, reader.pageFailingSince)
    }
}
