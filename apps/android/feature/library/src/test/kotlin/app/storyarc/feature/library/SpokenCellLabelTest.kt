package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a cover says out loud the two things it only draws.
 *
 * `library-browsing`: a publication that is neither on the device nor currently reachable
 * "is dimmed and still selectable", and "dimming is the only difference". Dimming is
 * nothing at all to a screen reader — so the fact has to be in the label, and a reader
 * using TalkBack or VoiceOver would otherwise meet a shelf where every cover sounds
 * identical and half of them cannot be opened.
 *
 * The same for the tick in the corner that means "this one is on the device", which is the
 * answer to the question a reader asks before boarding a train.
 *
 * iOS's `LibraryMarksTests` asserts the same order against `LibraryMarks.spoken`.
 */
class SpokenCellLabelTest {

    private val downloaded = "On this device"
    private val unavailable = "Needs its library to be reachable"

    private fun label(
        isOnDevice: Boolean = false,
        isReadableNow: Boolean = true,
        parts: List<String?> = listOf("Lantern Green #43", "Lantern Green", "CBZ"),
    ) = spokenCellLabel(
        parts = parts,
        isOnDevice = isOnDevice,
        isReadableNow = isReadableNow,
        downloaded = downloaded,
        unavailable = unavailable,
    )

    @Test
    fun `a row that needs its source says so, and not only by being dim`() {
        assertTrue(
            "A dimmed cover is silent to a screen reader. This is the sentence that is not.",
            label(isReadableNow = false).contains(unavailable),
        )
    }

    @Test
    fun `a row that can be opened says nothing extra`() {
        assertEquals("Lantern Green #43, Lantern Green, CBZ", label())
    }

    @Test
    fun `the marks come after what the publication is`() {
        // A reader skimming a shelf hears the title first. The marks are exceptions, not
        // descriptions, and a label that led with them would make every cover sound the
        // same for the first two words.
        assertEquals(
            "Lantern Green #43, Lantern Green, CBZ, $downloaded, $unavailable",
            label(isOnDevice = true, isReadableNow = false),
        )
    }

    @Test
    fun `on the device and reachable is one mark, not two`() {
        assertEquals("Lantern Green #43, Lantern Green, CBZ, $downloaded", label(isOnDevice = true))
    }

    @Test
    fun `a part the cell does not have is left out rather than spoken as a gap`() {
        // A publication with no series has no subtitle, and a label reading "Title, , CBZ"
        // is what a screen reader would say if the nulls were not dropped.
        assertEquals(
            "Lantern Green #43, CBZ",
            label(parts = listOf("Lantern Green #43", null, "CBZ")),
        )
    }
}
