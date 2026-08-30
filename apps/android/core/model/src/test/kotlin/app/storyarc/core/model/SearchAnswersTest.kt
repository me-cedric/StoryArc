package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one-search merge, asserted against the same table as iOS's `SearchAnswersTests`.
 *
 * `library-browsing` asks for local results now and remote results later, merged without
 * disturbing what the reader is already looking at. That promise is a property of this value
 * and of nothing else, so it is asserted here — case for case on both platforms, per
 * ADR-0001. Add a case here, add it there.
 */
class SearchAnswersTest {

    private fun local(title: String, kind: MatchKind = MatchKind.PUBLICATION) =
        SearchResult(kind = kind, title = title, publicationId = title)

    private fun remote(
        title: String,
        kind: MatchKind = MatchKind.PUBLICATION,
        from: String = "server",
    ) = SearchResult(kind = kind, title = title, route = SearchRoute(from, title))

    @Test
    fun `what the device holds is the whole answer until something else replies`() {
        val answers = SearchAnswers.of("bone", listOf(local("Bone")), listOf("server"))

        assertEquals(listOf("Bone"), answers.results.map { it.title })
        assertTrue(answers.isWaiting)
    }

    @Test
    fun `a late answer lands under what is already there and moves nothing`() {
        val before = SearchAnswers.of(
            "bone",
            listOf(local("Bone"), local("Bone Sharps")),
            listOf("server"),
        )
        val after = before.answered("server", listOf(remote("Boneyard")))

        assertEquals(listOf("Bone", "Bone Sharps", "Boneyard"), after.results.map { it.title })
        // The point of the whole type: everything the reader could already see is still
        // exactly where it was.
        assertEquals(before.results, after.results.take(2))
        assertFalse(after.isWaiting)
    }

    @Test
    fun `a server's copy of a book the device already holds is not a second row`() {
        val answers = SearchAnswers.of("bone", listOf(local("Bone")), listOf("server"))
            .answered("server", listOf(remote("bone"), remote("Boneyard")))

        assertEquals(listOf("Bone", "Boneyard"), answers.results.map { it.title })
        // The one that arrived first is the one that stayed, so the row still opens the copy
        // on the device rather than sending the reader to the network for it.
        assertEquals("Bone", answers.results.first().publicationId)
    }

    @Test
    fun `two books on the device that share a title are two rows not one`() {
        val first = SearchResult(MatchKind.PUBLICATION, "Volume 1", publicationId = "a")
        val second = SearchResult(MatchKind.PUBLICATION, "Volume 1", publicationId = "b")
        val answers = SearchAnswers.of("volume", listOf(first, second))

        // Folding these would lose a book from the reader's own shelf, which is a worse
        // failure than two rows that read alike.
        assertEquals(2, answers.results.size)
        assertEquals(2, answers.results.map { it.id }.toSet().size)
    }

    @Test
    fun `a server that matched one series twice sends one row`() {
        val answers = SearchAnswers.of("bone", asking = listOf("server")).answered(
            "server",
            listOf(
                remote("Bone", MatchKind.SERIES),
                remote("Bone", MatchKind.SERIES),
            ),
        )

        assertEquals(1, answers.results.size)
    }

    @Test
    fun `a late answer may add a heading and never above an existing one`() {
        val answers = SearchAnswers
            .of("smith", listOf(local("Smith's Journey")), listOf("server"))
            .answered("server", listOf(remote("Jeff Smith", MatchKind.PERSON)))

        assertEquals(
            listOf(MatchKind.PUBLICATION, MatchKind.PERSON),
            answers.groups.map { it.kind },
        )
    }

    @Test
    fun `headings come in the order something first had to go under them`() {
        val answers = SearchAnswers.of(
            "smith",
            listOf(local("Jeff Smith", MatchKind.PERSON), local("Smith's Journey")),
        )

        assertEquals(
            listOf(MatchKind.PERSON, MatchKind.PUBLICATION),
            answers.groups.map { it.kind },
        )
        assertEquals(listOf("Jeff Smith"), answers.groups.first().results.map { it.title })
    }

    @Test
    fun `a library that cannot answer leaves the results alone and is named once`() {
        val answers = SearchAnswers.of("bone", listOf(local("Bone")), listOf("server"))
            .couldNotAnswer("server", "Attic shelf")

        assertEquals(listOf("Bone"), answers.results.map { it.title })
        assertEquals(listOf("Attic shelf"), answers.silent.map { it.name })
        assertFalse(answers.isWaiting)
    }

    @Test
    fun `failing twice does not stack a second notice`() {
        val answers = SearchAnswers.of("bone", asking = listOf("server"))
            .couldNotAnswer("server", "Attic shelf")
            .couldNotAnswer("server", "Attic shelf")

        assertEquals(1, answers.silent.size)
    }

    @Test
    fun `trying a silent library again puts it back in the queue`() {
        val answers = SearchAnswers.of("bone", asking = listOf("server"))
            .couldNotAnswer("server", "Attic shelf")
            .askingAgain("server")

        assertTrue(answers.silent.isEmpty())
        assertEquals(listOf("server"), answers.waiting)
        assertTrue(answers.isWaiting)
    }

    @Test
    fun `a retry that succeeds clears the notice and appends what it found`() {
        val answers = SearchAnswers.of("bone", listOf(local("Bone")), listOf("server"))
            .couldNotAnswer("server", "Attic shelf")
            .askingAgain("server")
            .answered("server", listOf(remote("Boneyard")))

        assertTrue(answers.silent.isEmpty())
        assertEquals(listOf("Bone", "Boneyard"), answers.results.map { it.title })
    }

    @Test
    fun `two libraries answering in either order give the reader the same first row`() {
        val start = SearchAnswers.of("bone", listOf(local("Bone")), listOf("a", "b"))
        val oneWay = start
            .answered("a", listOf(remote("Boneyard", from = "a")))
            .answered("b", listOf(remote("Bone Sharps", from = "b")))
        val other = start
            .answered("b", listOf(remote("Bone Sharps", from = "b")))
            .answered("a", listOf(remote("Boneyard", from = "a")))

        assertEquals(oneWay.results.first(), other.results.first())
        assertEquals(oneWay.results.toSet(), other.results.toSet())
    }

    @Test
    fun `nothing typed and nothing found is no headings at all`() {
        assertTrue(SearchAnswers.of("").groups.isEmpty())
    }

    @Test
    fun `a person a server named is a row that plainly leads nowhere`() {
        val person = SearchResult(kind = MatchKind.PERSON, title = "Jeff Smith")

        assertFalse(person.isOpenable)
        assertNull(person.route)
        assertTrue(
            SearchResult(
                kind = MatchKind.PUBLICATION,
                title = "Bone",
                publicationId = "1",
            ).isOpenable,
        )
    }
}
