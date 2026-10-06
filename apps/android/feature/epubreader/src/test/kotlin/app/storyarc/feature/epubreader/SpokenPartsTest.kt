package app.storyarc.feature.epubreader

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The chapter list a read-aloud session shows.
 *
 * `audio-playback`, *Chapters*: "a publication with no chapter markers lists its parts in
 * playing order instead, rather than showing an empty list", and every surface that lists
 * them must list the same ones. A reflowable EPUB has no markers, so its reading order is
 * the list and its table of contents is what names the rows.
 *
 * Robolectric because Readium's `Link` is `@Parcelize` and `Href` parses a URL through
 * Android's own types. Nothing under test touches a device.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SpokenPartsTest {

    private fun link(href: String, title: String?, children: List<Link> = emptyList()) =
        Link(href = requireNotNull(Href(href)), title = title, children = children)

    @Test
    fun `one part per reading-order resource, in playing order`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("cover.xhtml", "ch1.xhtml", "ch2.xhtml"),
            titledBy = emptyList(),
        )

        assertEquals(3, parts.size)
    }

    @Test
    fun `the contents name the rows`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("ch1.xhtml", "ch2.xhtml"),
            titledBy = listOf("ch1.xhtml" to "The Harbour", "ch2.xhtml" to "The Crossing"),
        )

        assertEquals(listOf("The Harbour", "The Crossing"), parts.map { it.title })
    }

    @Test
    fun `an entry pointing inside a resource names a place, not the chapter`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("ch1.xhtml"),
            titledBy = listOf("ch1.xhtml#part-two" to "Part Two", "ch1.xhtml" to "The Harbour"),
        )

        assertEquals(listOf("The Harbour"), parts.map { it.title })
    }

    @Test
    fun `the first entry to name a resource is the one that names it`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("ch1.xhtml"),
            titledBy = listOf("ch1.xhtml" to "The Harbour", "ch1.xhtml" to "Something Later"),
        )

        assertEquals(listOf("The Harbour"), parts.map { it.title })
    }

    @Test
    fun `a resource the contents do not name carries no title of its own`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("cover.xhtml", "ch1.xhtml"),
            titledBy = listOf("ch1.xhtml" to "The Harbour"),
        )

        assertEquals(listOf("", "The Harbour"), parts.map { it.title })
    }

    @Test
    fun `a blank title names nothing, so the surface answers with a number`() {
        val parts = SpokenParts.of(
            readingOrder = listOf("ch1.xhtml"),
            titledBy = listOf("ch1.xhtml" to "   "),
        )

        assertEquals(listOf(""), parts.map { it.title })
    }

    @Test
    fun `no part states a length, so no surface states a total it guessed`() {
        val parts = SpokenParts.of(listOf("ch1.xhtml"), listOf("ch1.xhtml" to "The Harbour"))

        assertEquals(listOf(null), parts.map { it.duration.statedMillis })
    }

    @Test
    fun `a nested table of contents is read depth first`() {
        val titles = SpokenParts.titles(
            listOf(
                link("ch1.xhtml", "The Harbour", listOf(link("ch1.xhtml#two", "Part Two"))),
                link("ch2.xhtml", "The Crossing"),
            ),
        )

        assertEquals(
            listOf(
                "ch1.xhtml" to "The Harbour",
                "ch1.xhtml#two" to "Part Two",
                "ch2.xhtml" to "The Crossing",
            ),
            titles,
        )
    }

    @Test
    fun `an entry with no title at all contributes an empty one rather than being dropped`() {
        assertEquals(listOf("ch1.xhtml" to ""), SpokenParts.titles(listOf(link("ch1.xhtml", null))))
    }
}
