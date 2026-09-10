package app.storyarc.core.kavita

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That Kavita's two volume sentinels are recognised, and never drawn as numbers.
 *
 * A series whose chapters belong to no volume was headed **-100000** on a real server, and a
 * series with specials would have been headed **100000**. Both are Kavita's own private
 * numbers for "this is not a volume", quoted in [LOOSE_LEAF_VOLUME] and [SPECIAL_VOLUME].
 *
 * The specials number is **positive**, which is why the guard that already caught the chapter
 * sentinel did not catch this one. iOS's `VolumeSentinelTests` asserts the same table.
 */
class VolumeSentinelTest {

    private fun volume(number: Int) = KavitaVolume(id = 1, number = number)

    @Test
    fun `the current loose-leaf number is loose chapters`() {
        assertTrue(volume(LOOSE_LEAF_VOLUME).isLooseChapters)
        assertFalse(volume(LOOSE_LEAF_VOLUME).isSpecials)
    }

    @Test
    fun `zero is still loose chapters, because older servers say so`() {
        assertTrue(volume(0).isLooseChapters)
    }

    @Test
    fun `the specials number is specials, and it is positive`() {
        assertTrue(SPECIAL_VOLUME > 0)
        assertTrue(volume(SPECIAL_VOLUME).isSpecials)
        assertFalse(volume(SPECIAL_VOLUME).isLooseChapters)
    }

    @Test
    fun `a real volume is neither`() {
        listOf(1, 2, 17).forEach { number ->
            assertFalse(volume(number).isLooseChapters)
            assertFalse(volume(number).isSpecials)
        }
    }

    @Test
    fun `the numbers are the ones Kavita writes`() {
        // Quoted from `Kavita.Models/Constants/ParserConstants.cs`. A test rather than a
        // comment, because the whole defect was a number this app guessed at.
        org.junit.Assert.assertEquals(-100_000, LOOSE_LEAF_VOLUME)
        org.junit.Assert.assertEquals(100_000, SPECIAL_VOLUME)
    }
}
