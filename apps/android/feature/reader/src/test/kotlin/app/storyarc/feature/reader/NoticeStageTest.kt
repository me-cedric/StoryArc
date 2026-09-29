package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [NoticeStage] -- which of `network-share`'s two notices the reader is owed.
 *
 * The rule the dismissal defect turned on: the Dismiss button did nothing at all once the
 * notice stopped reading `SmbReachability`, and a dismissal that hid the notice for good would
 * never offer the download at 60 s. iOS's `NoticeStageTests` is the same table.
 */
class NoticeStageTest {
    @Test
    fun `a brief stall says nothing`() {
        assertNull(NoticeStage.of(blockedMillis = 1_999, dismissed = null))
    }

    @Test
    fun `past 2 s the notice shows, and past 60 s the offer`() {
        assertEquals(NoticeStage.BRIEF, NoticeStage.of(blockedMillis = 2_000, dismissed = null))
        assertEquals(NoticeStage.BRIEF, NoticeStage.of(blockedMillis = 59_999, dismissed = null))
        assertEquals(NoticeStage.LONG, NoticeStage.of(blockedMillis = 60_000, dismissed = null))
    }

    @Test
    fun `dismissing the brief notice still lets the offer appear at 60 s`() {
        assertNull(NoticeStage.of(blockedMillis = 30_000, dismissed = NoticeStage.BRIEF))
        assertEquals(NoticeStage.LONG, NoticeStage.of(blockedMillis = 60_000, dismissed = NoticeStage.BRIEF))
    }

    @Test
    fun `dismissing the offer hides it until the trouble ends`() {
        assertNull(NoticeStage.of(blockedMillis = 90_000, dismissed = NoticeStage.LONG))
    }
}
