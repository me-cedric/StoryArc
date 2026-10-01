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

    /** media3's own default for `maxSeekToPreviousPosition`. */
    private val restartWithin = 3_000L

    private fun target(positionMillis: Long, forward: Boolean) =
        chapterSeekTarget(offsets, positionMillis, forward, restartWithin)

    @Test
    fun `forward from the first chapter lands on the second`() {
        assertEquals(60_000L, target(positionMillis = 10_000, forward = true))
    }

    @Test
    fun `forward from the last chapter has nowhere to land`() {
        assertNull(target(positionMillis = 130_000, forward = true))
    }

    /** A car's back button: deep into a chapter, it hears the chapter again from its start. */
    @Test
    fun `back from deep inside a chapter restarts that chapter`() {
        assertEquals(120_000L, target(positionMillis = 130_000, forward = false))
    }

    @Test
    fun `back from just past a chapter's start lands on the chapter before`() {
        assertEquals(60_000L, target(positionMillis = 121_000, forward = false))
    }

    @Test
    fun `back from the start of the first chapter has nowhere to land`() {
        assertNull(target(positionMillis = 1_000, forward = false))
    }

    @Test
    fun `a folder's one window answers null in either direction`() {
        assertNull(chapterSeekTarget(emptyList(), 10_000, forward = true, restartWithin))
        assertNull(chapterSeekTarget(listOf(0L), 10_000, forward = false, restartWithin))
    }
}
