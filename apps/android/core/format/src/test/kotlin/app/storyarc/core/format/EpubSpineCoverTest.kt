package app.storyarc.core.format

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A cover for an EPUB that declares none.
 *
 * `publication-formats`: "WHEN an EPUB declares a cover image THEN that image is used;
 * otherwise the first page of the spine is rendered as the cover."
 *
 * Two halves, tested separately because they fail differently: finding the image a page
 * of XHTML points at is string work with a dozen shapes, and choosing between the
 * declared cover and that one is a rule over a real container. iOS's
 * `EpubSpineCoverTests` asserts the same cases in the same order.
 */
class EpubSpineCoverTest {
    private fun reader(name: String): EpubReader = runBlocking {
        EpubReader.open(FileSource(FixtureCorpus.file("ebooks/$name")))
    }

    private fun ebook(name: String): FixtureCorpus.Ebook =
        FixtureCorpus.ebooks.first { it.file == "ebooks/$name" }

    // ── Finding the image on the page ────────────────────────────────────────

    @Test
    fun `an img element's source is found`() {
        val page = """<html><body><img src="page1.png" width="2"/></body></html>""".toByteArray()
        assertEquals(listOf("page1.png"), EpubSpineCover.imageReferences(page))
    }

    @Test
    fun `an svg image is found too, however it spells its href`() {
        val namespaced = """<svg><image xlink:href="images/plate.jpg" /></svg>""".toByteArray()
        assertTrue(EpubSpineCover.imageReferences(namespaced).contains("images/plate.jpg"))
        val plain = "<svg><image href='images/plate.jpg'/></svg>".toByteArray()
        assertTrue(EpubSpineCover.imageReferences(plain).contains("images/plate.jpg"))
    }

    @Test
    fun `a css background is a picture too, quoted or not`() {
        val quoted = """<div style="background-image: url('bg.png')"></div>""".toByteArray()
        assertTrue(EpubSpineCover.imageReferences(quoted).contains("bg.png"))
        val bare = """<div style="background-image: url(bg.png)"></div>""".toByteArray()
        assertTrue(EpubSpineCover.imageReferences(bare).contains("bg.png"))
    }

    @Test
    fun `a page that points at nothing yields nothing`() {
        val page = "<html><body><h1>Title</h1><p>Words.</p></body></html>".toByteArray()
        assertTrue(EpubSpineCover.imageReferences(page).isEmpty())
    }

    @Test
    fun `a stylesheet link is not a cover`() {
        val page = """<head><link rel="stylesheet" href="style.css"/></head>""".toByteArray()
        assertEquals(listOf("style.css"), EpubSpineCover.imageReferences(page))
        assertFalse(EpubSpineCover.looksLikeAnImage("style.css"))
    }

    @Test
    fun `an href is resolved against the page that declared it, not against the root`() {
        assertEquals("OEBPS/page1.png", EpubSpineCover.resolve("page1.png", "OEBPS"))
        assertEquals("OEBPS/images/p.png", EpubSpineCover.resolve("../images/p.png", "OEBPS/text"))
        assertEquals("OEBPS/p.png", EpubSpineCover.resolve("/OEBPS/p.png", "OEBPS"))
        assertEquals("p.png", EpubSpineCover.resolve("p.png#anchor", ""))
    }

    // ── Choosing the cover ───────────────────────────────────────────────────

    @Test
    fun `a publication that declares a cover keeps it`() = runBlocking {
        for (name in listOf("fixture.epub", "epub2.epub", "fixed-layout.epub")) {
            val fixture = ebook(name)
            val resolved = reader(name).coverOrSpineHref()
            assertEquals(name, fixture.expectedCoverHref, resolved)
            assertEquals(name, fixture.expectedSpineCoverHref, resolved)
        }
    }

    @Test
    fun `a publication that declares none takes the image its first page shows`() = runBlocking {
        val fixture = ebook("spine-cover.epub")
        val reader = reader("spine-cover.epub")

        // Nothing is declared: this is the case the library used to draw a placeholder for.
        assertNull(reader.coverHref)
        assertEquals("OEBPS/page1.png", fixture.expectedSpineCoverHref)
        assertEquals(fixture.expectedSpineCoverHref, reader.coverOrSpineHref())
    }

    @Test
    fun `the cover found this way is a real entry, so its bytes read like any other`() =
        runBlocking {
            val reader = reader("spine-cover.epub")
            val href = requireNotNull(reader.coverOrSpineHref())
            val data = reader.data(href)
            assertTrue(data.isNotEmpty())
            assertEquals(PageCodec.PNG, PageCodec.of(data))
        }

    @Test
    fun `a first page of text alone leaves the publication without a cover`() = runBlocking {
        assertNull(ebook("series.epub").expectedSpineCoverHref)
        assertNull(reader("series.epub").coverOrSpineHref())
    }
}
