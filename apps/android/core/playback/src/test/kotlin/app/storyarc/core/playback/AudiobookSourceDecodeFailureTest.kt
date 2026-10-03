package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Where playback continues after a part fails to decode mid-playback. Task 16.5.
 *
 * Pure, the same reason `AudiobookChaptersTest` beside it is: `AudiobookSource.onPlayerError`
 * is the engine a real `Player` drives, and a test cannot reach it — this is the one decision
 * inside it a test can, lifted out for exactly that. iOS's `PlaybackTimelineTests` asserts
 * the identical two cases against `afterDecodeFailure(atPart:)`.
 */
class AudiobookSourceDecodeFailureTest {

    @Test
    fun `a failed part is followed by the next one, in a folder`() {
        assertEquals(1, afterDecodeFailure(PartLayout.FILES, index = 0, partCount = 3))
        assertEquals(2, afterDecodeFailure(PartLayout.FILES, index = 1, partCount = 3))
    }

    @Test
    fun `a failed last part ends the book, not a part past the end`() {
        assertNull(afterDecodeFailure(PartLayout.FILES, index = 2, partCount = 3))
    }

    @Test
    fun `a single file has no next part to move to, whichever chapter failed`() {
        // The whole file failed, not one chapter inside it — `MARKS` has nowhere else to go.
        assertNull(afterDecodeFailure(PartLayout.MARKS, index = 0, partCount = 3))
        assertNull(afterDecodeFailure(PartLayout.MARKS, index = 1, partCount = 3))
    }
}
