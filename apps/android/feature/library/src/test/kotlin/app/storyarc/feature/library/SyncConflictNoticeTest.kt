package app.storyarc.feature.library

import app.storyarc.core.model.ReadingPosition
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * D3's naming, in the unit each kind of position already keeps.
 *
 * iOS's `SyncConflictNoticeTests` asserts the same cases.
 */
class SyncConflictNoticeTest {

    @Test
    fun `a page position is named by its own index, one-based`() {
        assertEquals(
            "page 5 of 10",
            formatPosition(ReadingPosition.Page(4, 10), "page %1\$d of %2\$d", "%1\$d%%"),
        )
    }

    @Test
    fun `a reflowable position is named by its fraction, as a percentage`() {
        assertEquals(
            "50%",
            formatPosition(ReadingPosition.Reflowable(0.5, "{}"), "page %1\$d of %2\$d", "%1\$d%%"),
        )
    }
}
