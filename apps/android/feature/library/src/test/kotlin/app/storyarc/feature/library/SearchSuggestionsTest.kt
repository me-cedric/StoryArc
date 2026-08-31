package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the search page offers before a letter is typed.
 *
 * `navigation-shell`'s *What search opens onto*: the screen "presents recent searches, and
 * publications the reader already has — at least one in progress, one never opened, and one
 * that is next in a series they have read", and "every suggestion comes from the device or
 * from a source the reader configured, and **none is fetched in order to be suggested**".
 *
 * That last clause is why every one of these runs on a plain JVM with no store, no registry
 * and no client. The inputs are a list the app already holds and two closures the caller
 * answers from state it already has; there is nothing here that *could* wait on a server. A
 * test that needed one to pass would be proving the opposite of the requirement.
 *
 * **These three sections are a product choice, not a Material pattern.** Material knows only
 * historical suggestions before typing, and the change's `design.md` says so in as many
 * words: permitted, not prescribed. So they are asserted against the spec and nothing here
 * claims a guideline for them.
 */
class SearchSuggestionsTest {

    private val now = 1_700_000_000_000L
    private val day = 24L * 60L * 60L * 1000L

    @Test
    fun `the three sections are what the reader already has`() {
        val reading = publication("Harbour Lights", addedAt = now - 9 * day)
        val fresh = publication("Tin Kingdom", addedAt = now - day)
        val first = issue("Ashfall Wake", "1")
        val second = issue("Ashfall Wake", "2")

        val offer = suggestions(
            listOf(reading, fresh, first, second),
            progress = mapOf(
                reading.id to partRead(at = now - 2 * day),
                first.id to finished(at = now - 3 * day),
            ),
        )

        assertEquals(listOf("Harbour Lights"), offer.inProgress.map { it.publication.displayTitle })
        assertEquals(listOf("Ashfall Wake 2"), offer.nextInSeries.map { it.publication.displayTitle })
        assertEquals(listOf("Tin Kingdom"), offer.neverOpened.map { it.publication.displayTitle })
    }

    @Test
    fun `the next volume in a series is not offered a second time as never opened`() {
        // It **is** unread — that is half of what qualified it — so a plain unread filter
        // would list it twice, the second time under a heading that says less about it.
        // *Next in a series you have read* wins: "you finished volume 1, here is volume 2"
        // is a better thing to say about a book than "you have not opened this".
        val first = issue("Ashfall Wake", "1")
        val second = issue("Ashfall Wake", "2")

        val offer = suggestions(
            listOf(first, second),
            progress = mapOf(first.id to finished(at = now - day)),
        )

        assertEquals(listOf("Ashfall Wake 2"), offer.nextInSeries.map { it.publication.displayTitle })
        assertTrue(offer.neverOpened.isEmpty())
    }

    @Test
    fun `something part-read is offered once, and only as something to continue`() {
        val reading = publication("Harbour Lights")

        val offer = suggestions(
            listOf(reading),
            progress = mapOf(reading.id to partRead(at = now)),
        )

        assertEquals(1, offer.all.size)
        assertTrue(offer.nextInSeries.isEmpty())
        assertTrue(offer.neverOpened.isEmpty())
    }

    @Test
    fun `never opened leads with what arrived most recently`() {
        val old = publication("Paper Moon", addedAt = now - 30 * day)
        val recent = publication("The Glasswright", addedAt = now - day)

        val offer = suggestions(listOf(old, recent))

        assertEquals(
            listOf("The Glasswright", "Paper Moon"),
            offer.neverOpened.map { it.publication.displayTitle },
        )
    }

    @Test
    fun `an empty library has nothing to suggest, which is its own screen`() {
        // `navigation-shell`'s *Nothing to suggest*: the screen "says so in one sentence
        // rather than drawing empty headings". One flag rather than three empty lists
        // checked at the call site, so the screen cannot get the question half right.
        assertTrue(suggestions(emptyList()).isEmpty)
        assertFalse(suggestions(listOf(publication("Anything"))).isEmpty)
    }

    @Test
    fun `no section is longer than a search page has room for`() {
        // Search is never exhaustive; the library is, and typing a term is how a reader gets
        // there. An unbounded *never opened* over nine hundred publications would be the
        // shelf with a different heading over it.
        val library = (1..40).map { publication("Book $it", addedAt = now - it * day) }

        val offer = suggestions(library, sectionLength = 8)

        assertEquals(8, offer.neverOpened.size)
    }

    @Test
    fun `a suggestion that cannot be opened right now is still offered, and says so`() {
        // The same rule the home shelves keep: a shelf that shrank when the Wi-Fi went
        // "reads as lost reading", so an entry that cannot be opened stays and is dimmed.
        val away = publication("Away")

        val offer = suggestions(listOf(away), readable = { false })

        assertEquals(1, offer.neverOpened.size)
        assertFalse(offer.neverOpened.single().isReadableNow)
    }

    // Fixtures

    private fun suggestions(
        publications: List<Publication>,
        progress: Map<String, ReadingProgress> = emptyMap(),
        readable: (Publication) -> Boolean = { true },
        sectionLength: Int = SearchSuggestions.SECTION_LENGTH,
    ) = SearchSuggestions.of(
        publications = publications,
        progress = { progress[it.id] },
        isReadableNow = readable,
        sectionLength = sectionLength,
    )

    private fun publication(title: String, addedAt: Long? = now) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.EMBEDDED,
        addedAtEpochMillis = addedAt,
    )

    private fun issue(series: String, number: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$series-$number.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "$series $number",
        series = series,
        number = number,
        origin = MetadataOrigin.EMBEDDED,
        addedAtEpochMillis = now,
    )

    private fun partRead(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 4, total = 31),
        updatedAtEpochMillis = at,
    )

    private fun finished(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 30, total = 31),
        isFinished = true,
        finishedAtEpochMillis = at,
        updatedAtEpochMillis = at,
    )
}
