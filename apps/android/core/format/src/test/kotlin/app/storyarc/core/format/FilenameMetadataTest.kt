package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Driven entirely by the case table in the shared corpus manifest, so both
 * platforms agree on what "common naming pattern" means rather than each inventing
 * its own list. iOS's `FilenameMetadataTests` reads the same table.
 */
class FilenameMetadataTest {
    @Test
    fun `every case in the shared table parses as recorded`() {
        for (expected in FixtureCorpus.filenames) {
            val parsed = FilenameMetadata.of(expected.filename)
            val why = "${expected.filename}: ${expected.why}"
            assertEquals(why, expected.series, parsed.series)
            assertEquals(why, expected.number, parsed.number)
            assertEquals(why, expected.volume, parsed.volume)
            assertEquals(why, expected.year, parsed.year)
        }
    }

    @Test
    fun `the table covers more than one naming convention`() {
        // A guard on the corpus rather than on the parser: a table of one shape
        // would pass while proving nothing.
        assertTrue(FixtureCorpus.filenames.size >= 6)
    }

    @Test
    fun `everything inferred says that it is inferred`() {
        // `publication-formats` requires it: an authoritative source has to be able
        // to replace a guess without raising a conflict the app invented.
        assertTrue(FilenameMetadata.of("Anything 001 (2020).cbz").isInferred)
    }

    @Test
    fun `a name with nothing to infer still yields a title`() {
        val parsed = FilenameMetadata.of("Watchmen.cbz")
        assertEquals("Watchmen", parsed.series)
        assertNull(parsed.number)
    }

    @Test
    fun `an empty name infers nothing rather than an empty title`() {
        assertNull(FilenameMetadata.of("").series)
        assertNull(FilenameMetadata.of(".cbz").series)
    }

    @Test
    fun `a catalogue's series beats the filename`() {
        // A downloaded or cached publication is named after an identifier, not after
        // itself: an OPDS download lands as `urn-storyarc-6.cbz` and a Kavita chapter as
        // the chapter's id. `comic-reader` keeps per-series settings, and a series read
        // out of one of those names is a series of one.
        val parsed = FilenameMetadata.of("urn-storyarc-6.cbz", catalogued = "Quiet Machines")
        assertEquals("Quiet Machines", parsed.series)
    }

    @Test
    fun `a folder name still loses to the filename`() {
        // Unchanged, and the reason is unchanged: a folder name describes a shelf and a
        // filename describes the book on it. Only a catalogue outranks the book.
        val parsed = FilenameMetadata.of("Bone 01.cbz", seriesHint = "Comics")
        assertEquals("Bone", parsed.series)
    }
}
