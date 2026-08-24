package app.storyarc.core.format

import app.storyarc.core.model.ReadingDirection
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Asserted against the shared corpus. iOS's `ComicInfoTests` reads the same
 * manifest entries, so neither platform can privately decide what a field means.
 */
class ComicInfoTest {
    private suspend fun comicInfo(name: String): ComicInfo {
        val archive = ComicArchiveOpener.open(FixtureCorpus.file("comics/$name"))
        val data = (archive as ZipComicArchive).comicInfoData!!
        return ComicInfo.parse(data)!!
    }

    private fun parse(xml: String) = ComicInfo.parse(xml.toByteArray())

    @Test
    fun `every field the spec names is read`() = runTest {
        val info = comicInfo("manga-metadata.cbz")
        assertEquals("Fixture Manga", info.series)
        assertEquals("3", info.number)
        assertEquals(2, info.volume)
        assertEquals("The Third Chapter", info.title)
        assertEquals(listOf("A Penciller"), info.pencillers)
        assertEquals("Fixture Press", info.publisher)
        assertEquals(2026, info.year)
        assertEquals(1, info.month)
        assertEquals(15, info.day)
        assertEquals(4, info.pageCount)
        assertEquals("ja", info.language)
    }

    @Test
    fun `a creator field holds a list, because ComicInfo allows one`() = runTest {
        assertEquals(
            listOf("First Writer", "Second Writer"),
            comicInfo("manga-metadata.cbz").writers,
        )
    }

    @Test
    fun `xml entities in text are decoded`() = runTest {
        // Showing `&amp;` in a library is a bug a user sees immediately.
        assertEquals(
            "A summary with an & in it, to prove entities are decoded.",
            comicInfo("manga-metadata.cbz").summary,
        )
    }

    @Test
    fun `the issue number stays a string`() {
        // "3.5" and "Annual 1" are both real issue numbers, and rounding either
        // loses the publication's identity.
        assertEquals("3.5", parse("<ComicInfo><Number>3.5</Number></ComicInfo>")?.number)
    }

    // Reading direction.

    @Test
    fun `an explicit right-to-left declaration is honoured`() = runTest {
        val info = comicInfo("manga-metadata.cbz")
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, info.declaredDirection)
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, info.readingDirection)
    }

    @Test
    fun `japanese with no declared direction opens right-to-left`() = runTest {
        val info = comicInfo("japanese-no-direction.cbz")
        assertNull(info.declaredDirection)
        assertEquals("ja-JP", info.language)
        // The second branch of the rule, and the one a reader most often gets
        // wrong by keying on the wrong field.
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, info.readingDirection)
    }

    @Test
    fun `manga=yes does not declare a direction on its own`() {
        // It says the publication is manga, which is not the same as saying which
        // way it reads — plenty of manga are published left-to-right in
        // translation. So it falls through to the language rule.
        val info = parse("<ComicInfo><Manga>Yes</Manga><LanguageISO>en</LanguageISO></ComicInfo>")
        assertNull(info?.declaredDirection)
        assertEquals(ReadingDirection.LEFT_TO_RIGHT, info?.readingDirection)
    }

    @Test
    fun `manga=no declares left-to-right, overriding the language`() {
        val info = parse("<ComicInfo><Manga>No</Manga><LanguageISO>ja</LanguageISO></ComicInfo>")
        assertEquals(ReadingDirection.LEFT_TO_RIGHT, info?.declaredDirection)
        assertEquals(ReadingDirection.LEFT_TO_RIGHT, info?.readingDirection)
    }

    @Test
    fun `no metadata at all means left-to-right`() {
        assertEquals(
            ReadingDirection.LEFT_TO_RIGHT,
            parse("<ComicInfo></ComicInfo>")?.readingDirection,
        )
    }

    // The Pages list.

    @Test
    fun `a designated cover that is not page 1 is read`() = runTest {
        // `publication-formats`: the first page in reading order is the cover
        // *unless* ComicInfo designates another.
        assertEquals(1, comicInfo("manga-metadata.cbz").coverPageIndex)
    }

    @Test
    fun `designating page 0 as the cover is not treated as an override`() {
        // Index 0 is already the default, so a well-formed file that states it must
        // not look like it is asking for something different.
        val info = parse(
            """<ComicInfo><Pages><Page Image="0" Type="FrontCover"/></Pages></ComicInfo>""",
        )
        assertNull(info?.coverPageIndex)
    }

    @Test
    fun `double-page spreads are believed rather than guessed`() = runTest {
        // PageDecoder.isSpread is a heuristic over aspect ratio; this is a
        // statement by whoever made the file, so it wins.
        assertEquals(listOf(2), comicInfo("manga-metadata.cbz").doublePageIndices)
    }

    // Robustness.

    @Test
    fun `bytes that are not ComicInfo yield nothing`() {
        assertNull(parse("<Something/>"))
        assertNull(ComicInfo.parse(ByteArray(64) { 0xFF.toByte() }))
    }

    @Test
    fun `a ComicInfo with only a series still parses`() {
        // Common in real libraries, and a parser that requires more finds nothing.
        val info = parse("<ComicInfo><Series>Only This</Series></ComicInfo>")
        assertEquals("Only This", info?.series)
        assertNull(info?.number)
        assertTrue(info?.doublePageIndices?.isEmpty() == true)
    }

    @Test
    fun `an empty element is absent rather than an empty string`() {
        assertNull(parse("<ComicInfo><Series>   </Series></ComicInfo>")?.series)
    }

    @Test
    fun `a non-numeric year does not become a number`() {
        assertNull(parse("<ComicInfo><Year>MMXXVI</Year></ComicInfo>")?.year)
    }
}
