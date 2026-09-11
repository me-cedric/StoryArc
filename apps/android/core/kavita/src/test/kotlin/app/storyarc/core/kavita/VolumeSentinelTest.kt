package app.storyarc.core.kavita

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
        assertEquals(-100_000, LOOSE_LEAF_VOLUME)
        assertEquals(100_000, SPECIAL_VOLUME)
    }
}

/**
 * That a sentinel wearing a name is rejected too.
 *
 * The first guard tested the *number*. Kavita derives a chapter's title and a volume's name
 * from the number, so the same sentinel arrives as text, and the title is read first -- which
 * left the guard reachable around. iOS's `NameSentinelTests` asserts the same table.
 */
class NameSentinelTest {

    @Test
    fun `a sentinel is not a title`() {
        assertEquals("", KavitaChapter(id = 1, number = "", title = "-100000").displayName)
        assertEquals("", KavitaChapter(id = 1, number = "", title = "100000").displayName)
    }

    @Test
    fun `a real title survives, including one that is a number`() {
        assertEquals("3", KavitaChapter(id = 1, number = "", title = "3").displayName)
        assertEquals("Year One", KavitaChapter(id = 1, number = "", title = "Year One").displayName)
    }

    @Test
    fun `a real number still wins when the title is a sentinel`() {
        assertEquals("7", KavitaChapter(id = 1, number = "7", title = "-100000").displayName)
    }

    @Test
    fun `a sentinel is not a volume name`() {
        assertNull(KavitaVolume(id = 1, number = 1, name = "-100000").properName)
        assertNull(KavitaVolume(id = 1, number = 1, name = "100000").properName)
        assertEquals("Year One", KavitaVolume(id = 1, number = 1, name = "Year One").properName)
    }

    @Test
    fun `Kavita's own field decides what a volume is, before the older one`() {
        // `VolumeExtensions.IsLooseLeaf()` reads MinNumber. A server that sends only that
        // leaves `number` at zero, and zero alone would call a specials volume loose.
        val specials = KavitaVolume(id = 1, number = 0, minNumber = 100_000.0)
        assertTrue(specials.isSpecials)
        assertFalse(specials.isLooseChapters)

        val loose = KavitaVolume(id = 1, number = 0, minNumber = -100_000.0)
        assertTrue(loose.isLooseChapters)

        // A fractional volume is a real volume, and neither.
        val half = KavitaVolume(id = 1, number = 1, minNumber = 1.5)
        assertFalse(half.isLooseChapters)
        assertFalse(half.isSpecials)
    }
}
