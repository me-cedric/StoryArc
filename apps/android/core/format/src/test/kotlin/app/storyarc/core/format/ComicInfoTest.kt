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

    // Genre and tags.
    //
    // Asserted against XML written here rather than against the corpus: the shared
    // fixtures carry no `<Genre>` or `<Tags>`, and `library-browsing` needs both
    // filters covered without regenerating a corpus both platforms' format tests are
    // pinned to. iOS's `ComicInfoTests` asserts the same four cases.

    @Test
    fun `genre and tags are separate lists, comma-split like every other list field`() {
        val info = parse(
            "<ComicInfo>" +
                "<Genre>Superhero, Mystery</Genre>" +
                "<Tags>reprint,annual</Tags>" +
                "</ComicInfo>",
        )
        assertEquals(listOf("Superhero", "Mystery"), info?.genres)
        assertEquals(listOf("reprint", "annual"), info?.tags)
    }

    @Test
    fun `a file that names neither yields empty lists rather than nothing`() {
        // "Present but empty" and "absent" are the same to a filter, and a nullable
        // list would offer a distinction nothing can act on.
        val info = parse("<ComicInfo><Series>Bone</Series></ComicInfo>")
        assertEquals(emptyList<String>(), info?.genres)
        assertEquals(emptyList<String>(), info?.tags)
    }

    @Test
    fun `an empty element is not a genre called nothing`() {
        assertEquals(emptyList<String>(), parse("<ComicInfo><Genre></Genre></ComicInfo>")?.genres)
    }

    @Test
    fun `an entity inside a genre is decoded, as it is everywhere else`() {
        val info = parse("<ComicInfo><Genre>Sword &amp; Sorcery</Genre></ComicInfo>")
        assertEquals(listOf("Sword & Sorcery"), info?.genres)
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

/**
 * Cover selection is its own class because the rule spans every container: the
 * first page in reading order, unless `ComicInfo.xml` designates another.
 */
class CoverSelectionTest {
    @Test
    fun `a designated cover wins over the first page`() = runTest {
        ComicArchiveOpener.open(FixtureCorpus.file("comics/manga-metadata.cbz")).use { archive ->
            // The fixture designates index 1, so the second page is the cover.
            assertEquals("p2.png", archive.coverPage?.path)
            assertEquals("p1.png", archive.pages.first().path)
        }
    }

    @Test
    fun `without metadata the first page in reading order is the cover`() = runTest {
        for (name in listOf("natural-sort.cbz", "tar-store.cbt", "rar5-store.cbr")) {
            ComicArchiveOpener.open(FixtureCorpus.file("comics/$name")).use { archive ->
                assertEquals(name, archive.pages.first(), archive.coverPage)
            }
        }
    }

    @Test
    fun `reading order decides, not archive order`() = runTest {
        // The cover is the first page a reader sees, not the first entry a parser
        // meets.
        ComicArchiveOpener.open(FixtureCorpus.file("comics/natural-sort.cbz")).use { archive ->
            assertEquals("page1.png", archive.coverPage?.path)
        }
    }

    @Test
    fun `a designated index outside the page list is ignored, not clamped`() {
        val pages = listOf(PageEntry("a.png", 1), PageEntry("b.png", 1))
        // ComicInfo counts archive entries, so filtering out non-page entries can
        // leave a stale index. An arbitrary middle page would look like a bug in
        // the reader rather than in the file.
        assertEquals("a.png", CoverSelection.cover(pages, 9)?.path)
        assertEquals("a.png", CoverSelection.cover(pages, -1)?.path)
        assertEquals("b.png", CoverSelection.cover(pages, 1)?.path)
    }

    @Test
    fun `a publication with no pages has no cover`() = runTest {
        ComicArchiveOpener.open(FixtureCorpus.file("comics/no-pages.cbz")).use { archive ->
            assertNull(archive.coverPage)
        }
    }

    @Test
    fun `an epub's declared cover is used`() = runTest {
        val reader = EpubReader.open(FileSource(FixtureCorpus.file("ebooks/fixture.epub")))
        assertEquals("OEBPS/cover.png", reader.coverHref)
        // `publication-formats` also says a publication with no declared cover
        // falls back to rendering the first spine item. That needs a renderer, so
        // it lands with the reflowable reader — recorded here rather than silently
        // missing.
    }
}
