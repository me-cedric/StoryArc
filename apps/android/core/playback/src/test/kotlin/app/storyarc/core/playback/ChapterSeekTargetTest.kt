package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Where a car's next/previous press lands inside one chaptered file.
 *
 * `audio-playback`: a car's next-track control moves a chapter rather than a file.
 * [ChapterSeekingPlayer] is the caller that cannot be built without a real `ExoPlayer` and a
 * decoded container; this is the part of it that can, pulled out as a plain function over the
 * offsets [AudiobookChapters.offsets] already produces.
 */
class ChapterSeekTargetTest {

    /** Three chapters: 0, one minute, two minutes. */
    private val offsets = listOf(0L, 60_000L, 120_000L)

    @Test
    fun `forward from the first chapter lands on the second`() {
        assertEquals(60_000L, chapterSeekTarget(offsets, positionMillis = 10_000, forward = true))
    }

    @Test
    fun `forward from the last chapter has nowhere to land`() {
        assertNull(chapterSeekTarget(offsets, positionMillis = 130_000, forward = true))
    }

    @Test
    fun `back from the middle of the last chapter lands on the second`() {
        assertEquals(60_000L, chapterSeekTarget(offsets, positionMillis = 130_000, forward = false))
    }

    @Test
    fun `back from the first chapter has nowhere to land`() {
        assertNull(chapterSeekTarget(offsets, positionMillis = 10_000, forward = false))
    }

    @Test
    fun `a folder's one window answers null in either direction`() {
        assertNull(chapterSeekTarget(emptyList(), positionMillis = 10_000, forward = true))
        assertNull(chapterSeekTarget(listOf(0L), positionMillis = 10_000, forward = false))
    }
}
