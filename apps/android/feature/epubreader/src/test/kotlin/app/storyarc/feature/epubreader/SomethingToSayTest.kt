package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `ebook-reader`, *A publication with nothing to say*: "the read-aloud control is absent
 * rather than present and refusing".
 *
 * Readium gives every reflowable EPUB a content service, so the old answer -- a service
 * exists -- said yes to a book of bare images, and play then walked to the end in silence.
 * The walk is handed the content an image-only book yields, which no fixture in the corpus
 * has; the fixture itself goes through [SpokenSentences.isSpeakable] whole. iOS asserts the
 * same rule in `SomethingToSayTests`.
 */
@OptIn(ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SomethingToSayTest {

    @Test
    fun `a book of bare images has nothing to say`() = runBlocking {
        assertFalse(SpokenSentences.hasWord(walk((0 until 3).map { image("page-$it.xhtml") })))
    }

    @Test
    fun `one paragraph after the images is enough`() = runBlocking {
        assertTrue(SpokenSentences.hasWord(walk(listOf(image("page-0.xhtml"), paragraph("Call me Ishmael.", "page-1.xhtml")))))
    }

    @Test
    fun `a paragraph of white space says nothing`() = runBlocking {
        assertFalse(SpokenSentences.hasWord(walk(listOf(paragraph(" \n\t", "page-0.xhtml")))))
    }

    @Test
    fun `the walk gives up past its bound of resources`() = runBlocking {
        val images = (0 until 60).map { image("page-$it.xhtml") }
        assertFalse(SpokenSentences.hasWord(walk(images + paragraph("Too late to count.", "page-60.xhtml"))))
    }

    @Test
    fun `no content service at all has nothing to say`() = runBlocking {
        assertFalse(SpokenSentences.hasWord(null))
    }

    @Test
    fun `a book of prose has something to say on its first pages`() = runBlocking {
        val file = corpus.resolve("ebooks/fixture.epub")
        val model = EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = file.absolutePath,
            identity = PublicationIdentity(normalizedPath = file.absolutePath),
            progress = null,
        )
        val publication = requireNotNull(model.open()) { "fixture failed to open" }
        assertTrue(SpokenSentences.isSpeakable(publication))
    }

    /** The committed fixture corpus, from this module's own directory rather than a walk. */
    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.epubreader.projectDir")) {
            "storyarc.epubreader.projectDir is not set -- see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private fun locator(href: String) = Locator(href = requireNotNull(Url(href)), mediaType = MediaType.XHTML)

    private fun image(href: String): Content.Element =
        Content.ImageElement(locator(href), Link(href = requireNotNull(Url("image.png"))), caption = null, attributes = emptyList())

    private fun paragraph(text: String, href: String): Content.Element = Content.TextElement(
        locator = locator(href),
        role = Content.TextElement.Role.Body,
        segments = listOf(Content.TextElement.Segment(locator(href), text, attributes = emptyList())),
        attributes = emptyList(),
    )

    /** A publication's content as a fixed list, in reading order. */
    private fun walk(elements: List<Content.Element>) = object : Content.Iterator {
        private var index = -1

        override suspend fun hasNext() = index + 1 < elements.size

        override fun next(): Content.Element = elements[++index]

        override suspend fun hasPrevious() = index > 0

        override fun previous(): Content.Element = elements[--index]
    }
}
