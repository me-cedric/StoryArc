package app.storyarc

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.playback.PlaybackPosition
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Where a car's shelf row resumes, from `reading-progress`'s own record.
 *
 * `audio-playback`: a shelf row resumes where the listener stopped. `CarLibrary.asPlayed`
 * used to answer every row at its own zero, so a car always offered a finished book's first
 * chapter again. [carBookPosition] is the rule [CarShelf.carBook] applies; this is the part of
 * it a plain JVM test can reach without a `Publication`, a `ContentResolver` and
 * [OpenedAudiobook].
 */
class CarShelfPositionTest {

    private val identity = PublicationIdentity(normalizedPath = "/audiobooks/sea-room.m4b")

    private fun recorded(part: Int, offsetMillis: Long, isFinished: Boolean = false) =
        ReadingProgress(
            identity = identity,
            position = ReadingPosition.Listening(
                part = part,
                partCount = 3,
                offsetMillis = offsetMillis,
                ofMillis = 300_000,
            ),
            isFinished = isFinished,
            updatedAtEpochMillis = 0,
        )

    @Test
    fun `a book nobody has played resumes at the beginning`() {
        assertEquals(PlaybackPosition(0, 0), carBookPosition(null))
    }

    @Test
    fun `a book in progress resumes where the listener stopped`() {
        assertEquals(
            PlaybackPosition(1, 45_000),
            carBookPosition(recorded(part = 1, offsetMillis = 45_000)),
        )
    }

    /** `ListenedPosition.resume`'s own rule: a finished book starts over, not one page short. */
    @Test
    fun `a finished book resumes at the beginning, not one part short of the end`() {
        assertEquals(
            PlaybackPosition(0, 0),
            carBookPosition(recorded(part = 2, offsetMillis = 598_000, isFinished = true)),
        )
    }

    @Test
    fun `a page position is not a listening position, so it resumes at the beginning`() {
        val paged = ReadingProgress(
            identity = identity,
            position = ReadingPosition.Page(index = 4, total = 10),
            updatedAtEpochMillis = 0,
        )

        assertEquals(PlaybackPosition(0, 0), carBookPosition(paged))
    }
}
