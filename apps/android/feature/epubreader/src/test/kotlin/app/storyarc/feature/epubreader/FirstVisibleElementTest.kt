package app.storyarc.feature.epubreader

import app.storyarc.core.model.ElementLocator
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.html.cssSelector
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `reading-progress`, *Resume at the first visible element*, decision O27, through
 * [EpubReaderViewModel.initialLocator]. iOS's `FirstVisibleElementTests` makes the same
 * assertions.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FirstVisibleElementTest {

    private val identity = PublicationIdentity(contentDigest = "d2")

    /** The place a fraction names: page 3 of chapter one, one page after the element's page. */
    private val fraction = """{"href":"OEBPS/ch1.xhtml","type":"application/xhtml+xml",
        "locations":{"progression":0.52,"totalProgression":0.26}}"""

    private fun element(href: String = "OEBPS/ch1.xhtml", digest: String = "d2") = ElementLocator(
        href = href,
        cssSelector = "body > p:nth-child(18)",
        textBefore = "the end of seventeen. ",
        textAfter = "Paragraph eighteen begins",
        publicationDigest = digest,
    )

    private suspend fun resumed(element: ElementLocator) = run {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        progress.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Reflowable(0.26, fraction, element),
                updatedAtEpochMillis = 0,
            ),
        )
        EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = "/nowhere.epub",
            identity = identity,
            progress = progress,
        ).initialLocator()
    }

    @Test
    fun `a stored element wins over a fraction that points one page away`() = runTest {
        val locator = resumed(element())!!

        assertEquals("body > p:nth-child(18)", locator.locations.cssSelector)
        assertEquals("Paragraph eighteen begins", locator.text.highlight)
        assertEquals("the end of seventeen. ", locator.text.before)
        assertEquals("OEBPS/ch1.xhtml", locator.href.toString())
    }

    @Test
    fun `a different resource falls back to the fraction`() = runTest {
        val locator = resumed(element(href = "OEBPS/ch2.xhtml"))!!

        assertNull(locator.locations.cssSelector)
        assertNull(locator.text.highlight)
        assertEquals(0.52, locator.locations.progression!!, 0.0)
    }

    @Test
    fun `a different file falls back to the fraction`() = runTest {
        assertNull(resumed(element(digest = "d9"))!!.locations.cssSelector)
    }

    @Test
    fun `the script's answer becomes the element, and no answer becomes none`() {
        val answer = """{"cssSelector":"body > p:nth-child(18)","before":"the end of seventeen. ",
            "after":"Paragraph eighteen begins"}"""

        assertEquals(element(), FirstVisibleElement.parse(answer, "OEBPS/ch1.xhtml", "d2"))
        assertNull(FirstVisibleElement.parse("null", "OEBPS/ch1.xhtml", "d2"))
        assertNull(FirstVisibleElement.parse(null, "OEBPS/ch1.xhtml", "d2"))
        assertNull(FirstVisibleElement.parse(answer, "OEBPS/ch1.xhtml", null))
    }
}
