package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a listener stopped, and why it is a third case rather than a second store.
 *
 * `reading-progress`:
 *
 * > **THEN** it is an offset in time within a named part, and a percentage is derived from
 * > the total duration
 * > … **AND** there is one position, and it is wherever the reader last was by either
 * > means, because it is one publication
 *
 * A publication read aloud and then read silently has **one** position, so an audiobook's
 * place cannot live in a store of its own — it has to be a [ReadingPosition], which is what
 * the progress merge, the finished rule and the library shelves all deal in.
 *
 * **The two rules the new case must not break**, and both are load-bearing:
 *
 * 1. [ReadingPosition.fraction] is the currency the whole merge deals in and
 *    [ReadingPosition.matches] compares by it. A listening position that answered on a
 *    different scale would make ADR-0006's first row unreachable for audiobooks, exactly as
 *    case equality once did for `Page`.
 * 2. It must answer **without** a duration. A read-aloud session has no true one —
 *    `PlaybackDuration.Estimated` exists on both platforms so an estimate can never be
 *    presented as exact — so the honest answer there is the part index over the part count,
 *    not a guess dressed up as a measurement.
 *
 * iOS's `ListeningPositionTests` asserts the same table.
 */
class ListeningPositionTest {

    // MARK: the fraction, with a duration

    @Test
    fun `the start of the first part is the start of the publication`() {
        val position = ReadingPosition.Listening(0, 4, 0, 300_000)
        assertEquals(0.0, position.fraction, 0.0)
    }

    @Test
    fun `half way through the second of four parts is three eighths`() {
        val position = ReadingPosition.Listening(1, 4, 150_000, 300_000)
        assertEquals(0.375, position.fraction, 0.0001)
    }

    @Test
    fun `the end of the last part is the end of the publication`() {
        val position = ReadingPosition.Listening(3, 4, 300_000, 300_000)
        assertEquals(1.0, position.fraction, 0.0001)
    }

    // MARK: the fraction, with no duration

    /**
     * The read-aloud case. `of` is null and the answer is the part, not an estimate.
     *
     * It never reaches 1.0, and that is the honesty: without a duration nothing knows how
     * much of the last part is left, and claiming the end of a publication is what marks it
     * finished.
     */
    @Test
    fun `with no duration the fraction is the part over the part count`() {
        assertEquals(0.0, ReadingPosition.Listening(0, 4, 90_000, null).fraction, 0.0)
        assertEquals(0.25, ReadingPosition.Listening(1, 4, 90_000, null).fraction, 0.0001)
        assertEquals(0.75, ReadingPosition.Listening(3, 4, 90_000, null).fraction, 0.0001)
    }

    @Test
    fun `an offset with no duration behind it does not move the fraction`() {
        val early = ReadingPosition.Listening(1, 4, 1_000, null)
        val late = ReadingPosition.Listening(1, 4, 900_000, null)
        assertEquals(early.fraction, late.fraction, 0.0)
    }

    // MARK: the edges

    @Test
    fun `a publication with one part and no duration is at its start`() {
        assertEquals(0.0, ReadingPosition.Listening(0, 1, 0, null).fraction, 0.0)
    }

    @Test
    fun `a part count of zero is not a division by zero`() {
        assertEquals(0.0, ReadingPosition.Listening(0, 0, 0, null).fraction, 0.0)
        assertEquals(0.0, ReadingPosition.Listening(0, 0, 5_000, 10_000).fraction, 0.0)
    }

    @Test
    fun `an offset past the end of its part does not run past the publication`() {
        val position = ReadingPosition.Listening(3, 4, 999_000, 300_000)
        assertEquals(1.0, position.fraction, 0.0)
    }

    @Test
    fun `a part with no length is at the start of that part`() {
        assertEquals(0.5, ReadingPosition.Listening(1, 2, 4_000, 0).fraction, 0.0001)
    }

    // MARK: rule 1 — the same currency as every other position

    @Test
    fun `a listening position matches a page position at the same fraction`() {
        val listening = ReadingPosition.Listening(1, 2, 0, 100_000)
        // Page 2 of 3: the middle, on the same 0..1 scale.
        assertTrue(listening.matches(ReadingPosition.Page(1, 3)))
        assertTrue(ReadingPosition.Page(1, 3).matches(listening))
    }

    /**
     * The row of ADR-0006's table that case equality used to make unreachable.
     *
     * The store keeps a synced position as a bare fraction — `Reflowable(fraction, "")` — so
     * a listening position that could never equal the one it had just been stored from would
     * report the local side as moved on every sync, for ever.
     */
    @Test
    fun `a listening position matches the bare fraction it was stored as`() {
        val listening = ReadingPosition.Listening(1, 4, 150_000, 300_000)
        assertTrue(listening.matches(ReadingPosition.Reflowable(listening.fraction, "")))
    }

    @Test
    fun `a merge sees a listener further on than a reader`() {
        val identity = PublicationIdentity(normalizedPath = "/books/sea-room.m4b")
        val synced = ReadingPosition.Listening(0, 4, 0, 300_000)
        val local = ReadingProgress(
            identity = identity,
            position = synced,
            updatedAtEpochMillis = 1_000,
            syncedPosition = synced,
        )
        val remote = local.copy(
            position = ReadingPosition.Listening(2, 4, 0, 300_000),
            updatedAtEpochMillis = 2_000,
        )

        val outcome = ProgressMerge.merge(local, remote)

        assertTrue(outcome is ProgressMergeOutcome.AdoptRemote)
    }

    // MARK: rule 2 — one publication, one position

    /**
     * `reading-progress`: "there is one position, and it is wherever the reader last was by
     * either means".
     *
     * Nothing here enforces that beyond the case being a [ReadingPosition] — which is the
     * enforcement. There is one field on [ReadingProgress] and one row in the store, so a
     * publication cannot hold a reading place and a listening place at once. This asserts
     * that the second replaces the first rather than sitting beside it.
     */
    @Test
    fun `listening replaces the place a reader left, rather than joining it`() {
        val identity = PublicationIdentity(normalizedPath = "/books/sea-room.epub")
        val read = ReadingProgress(
            identity = identity,
            position = ReadingPosition.Reflowable(0.2, "{}"),
            updatedAtEpochMillis = 1_000,
        )

        val listened = read.copy(
            position = ReadingPosition.Listening(1, 4, 0, 300_000),
            updatedAtEpochMillis = 2_000,
        )

        assertEquals(ReadingPosition.Listening(1, 4, 0, 300_000), listened.position)
        assertFalse(listened.position is ReadingPosition.Reflowable)
    }
}
