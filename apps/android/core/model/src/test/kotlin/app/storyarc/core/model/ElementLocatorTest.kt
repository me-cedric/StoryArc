package app.storyarc.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `reading-progress`, *Resume at the first visible element*, decision O27. iOS's
 * `ElementLocatorTests` asserts the same rows.
 */
class ElementLocatorTest {

    private val element = ElementLocator(
        href = "OEBPS/ch1.xhtml",
        cssSelector = "body > p:nth-child(18)",
        textBefore = "the end of seventeen. ",
        textAfter = "Paragraph eighteen begins",
        publicationDigest = "d2",
    )

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `the same file and the same resource resume at the element`() {
        assertTrue(element.resumes("d2", "OEBPS/ch1.xhtml"))
        assertTrue(element.resumes("d2", "OEBPS/ch1.xhtml#p18"))
    }

    @Test
    fun `another resource or another file falls back to the fraction`() {
        assertFalse(element.resumes("d2", "OEBPS/ch2.xhtml"))
        assertFalse(element.resumes("d9", "OEBPS/ch1.xhtml"))
        assertFalse(element.resumes(null, "OEBPS/ch1.xhtml"))
    }

    private fun captured(selector: String? = "p", after: String? = "Text", digest: String? = "d2") =
        ElementLocator.captured("ch1", selector, null, after, digest)

    @Test
    fun `nothing is captured without a digest, a selector or visible text`() {
        assertNotNull(captured())
        assertNull(captured(digest = null))
        assertNull(captured(selector = ""))
        assertNull(captured(after = " \n "))
    }

    @Test
    fun `each side keeps at most the limit, nearest the point`() {
        val long = "a".repeat(100) + "B"
        val kept = ElementLocator.captured("ch1", "p", long, "C$long", "d2")!!

        assertEquals(ElementLocator.TEXT_LIMIT, kept.textBefore?.length)
        assertTrue(kept.textBefore!!.endsWith("B"))
        assertEquals(ElementLocator.TEXT_LIMIT, kept.textAfter.length)
        assertTrue(kept.textAfter.startsWith("C"))
    }

    @Test
    fun `a document position without the element reads, and the element round-trips`() {
        val older = """{"kind":"reflowable","progression":0.45,"locator":""}"""
        assertEquals(
            ReadingPosition.Reflowable(0.45, ""),
            json.decodeFromString<DocumentPosition>(older).position(),
        )

        val position = ReadingPosition.Reflowable(0.45, "", element)
        val written = json.encodeToString(DocumentPosition(position))
        assertEquals(position, json.decodeFromString<DocumentPosition>(written).position())
    }

    @Test
    fun `an element this build cannot read is dropped and the fraction stays`() {
        val newer = """{"kind":"reflowable","progression":0.45,"locator":"","firstVisibleElement":{"href":"ch1"}}"""

        assertEquals(
            ReadingPosition.Reflowable(0.45, ""),
            json.decodeFromString<DocumentPosition>(newer).position(),
        )
    }

    @Test
    fun `a field inside the element that this build does not know is ignored`() {
        val newer = """
            {"kind":"reflowable","progression":0.45,"locator":"","firstVisibleElement":{"href":"OEBPS/ch1.xhtml",
            "cssSelector":"body > p:nth-child(18)","textBefore":"the end of seventeen. ",
            "textAfter":"Paragraph eighteen begins","publicationDigest":"d2","fontScale":1.15}}
        """.trimIndent()

        assertEquals(
            ReadingPosition.Reflowable(0.45, "", element),
            json.decodeFromString<DocumentPosition>(newer).position(),
        )
    }
}
