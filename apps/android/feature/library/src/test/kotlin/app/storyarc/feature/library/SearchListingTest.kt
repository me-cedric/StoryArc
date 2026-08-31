package app.storyarc.feature.library

import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.SearchResult
import app.storyarc.core.model.SearchRoute
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The one-search merge, asserted against the same table as iOS's `SearchListingTests`.
 *
 * `library-browsing` asks for local results now and remote results later, merged into one
 * ranked list with each row labelled, and without disturbing what the reader is already looking
 * at. That promise is a property of this value and of nothing else, so it is asserted here —
 * case for case on both platforms, per ADR-0001. Add a case here, add it there.
 */
class SearchListingTest {

    private val folder = SearchOrigin.Library("folder", "Attic NAS")
    private val server = SearchOrigin.Library("server", "Reading Room")

    private fun held(
        title: String,
        kind: MatchKind = MatchKind.PUBLICATION,
        origin: SearchOrigin = folder,
        id: String = title,
    ) = FoundRow(SearchResult(kind = kind, title = title, publicationId = id), origin)

    private fun away(
        title: String,
        kind: MatchKind = MatchKind.PUBLICATION,
        origin: SearchOrigin = server,
    ) = FoundRow(
        SearchResult(kind = kind, title = title, route = SearchRoute(origin.key, title)),
        origin,
    )

    private fun publication(title: String, sourceId: UUID?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    @Test
    fun `what the device holds is the whole answer until something else replies`() {
        val listing = SearchListing.of("bone", local = listOf(held("Bone")), asking = listOf("server"))
        assertEquals(listOf("Bone"), listing.rows.map { it.result.title })
        assertTrue(listing.isWaiting)
    }

    @Test
    fun `a late answer lands under what is already there and moves nothing`() {
        val before = SearchListing.of(
            "bone",
            local = listOf(held("Carbone")),
            asking = listOf("server"),
        )
        val after = before.answered("server", listOf(away("Bone")))
        // The server's row answers better and still goes underneath: the promise that nothing
        // already on screen moves outranks the ranking itself.
        assertEquals(listOf("Carbone", "Bone"), after.rows.map { it.result.title })
        assertFalse(after.isWaiting)
    }

    @Test
    fun `one answer is ranked within itself before it is appended`() {
        val listing = SearchListing.of("bone", asking = listOf("server"))
            .answered("server", listOf(away("Carbone"), away("Bone Up"), away("Bone")))
        assertEquals(
            listOf("Bone", "Bone Up", "Carbone"),
            listing.rows.map { it.result.title },
        )
    }

    @Test
    fun `the device's own answer is ranked by the same rule`() {
        val listing = SearchListing.of("bone", local = listOf(held("Carbone"), held("Bone")))
        assertEquals(listOf("Bone", "Carbone"), listing.rows.map { it.result.title })
    }

    @Test
    fun `two libraries that both hold a book are two labelled rows`() {
        // The photographed defect. A catalogue served exactly one match, the device held a book
        // of the same title, and the catalogue's answer never reached the screen.
        val listing = SearchListing.of("fine print", local = listOf(held("Fine Print")))
            .answered("server", listOf(away("Fine Print")))
        assertEquals(2, listing.rows.size)
        assertEquals(listOf(folder, server), listing.rows.map { it.origin })
    }

    @Test
    fun `a library that says the same thing twice is folded into one row`() {
        val listing = SearchListing.of("bone", asking = listOf("server"))
            .answered("server", listOf(away("Bone"), away("Bone")))
        assertEquals(1, listing.rows.size)
    }

    @Test
    fun `a server's copy of a book downloaded from that same server folds away`() {
        // A chapter fetched from a library carries that library's identity, so the copy on the
        // device and the copy on the server are one row — the one that opens on a plane.
        val listing = SearchListing.of("bone", local = listOf(held("Bone", origin = server)))
            .answered("server", listOf(away("Bone")))
        assertEquals(1, listing.rows.size)
        assertEquals("Bone", listing.rows[0].result.publicationId)
    }

    @Test
    fun `two books of one title in one library are two books`() {
        val listing = SearchListing.of(
            "bone",
            local = listOf(held("Bone", id = "one"), held("Bone", id = "two")),
        )
        assertEquals(2, listing.rows.size)
    }

    @Test
    fun `a heading appears in the order its first row did`() {
        val listing = SearchListing.of(
            "bone",
            local = listOf(held("Carbone")),
            asking = listOf("server"),
        ).answered("server", listOf(away("Bone", MatchKind.SERIES)))
        assertEquals(
            listOf(MatchKind.PUBLICATION, MatchKind.SERIES),
            listing.groups.map { it.kind },
        )
        assertEquals(listOf(1, 1), listing.groups.map { it.rows.size })
    }

    @Test
    fun `a library that could not answer is named once however often it is asked`() {
        val listing = SearchListing.of("bone", asking = listOf("server"))
            .couldNotAnswer("server", "Reading Room")
            .couldNotAnswer("server", "Reading Room")
        assertEquals(listOf("Reading Room"), listing.silent.map { it.name })
        assertFalse(listing.isWaiting)
    }

    @Test
    fun `a library that fails leaves the rows already on screen alone`() {
        val listing = SearchListing.of(
            "bone",
            local = listOf(held("Bone")),
            asking = listOf("server"),
        ).couldNotAnswer("server", "Reading Room")
        assertEquals(listOf("Bone"), listing.rows.map { it.result.title })
    }

    @Test
    fun `asking a silent library again puts it back in the queue`() {
        val listing = SearchListing.of("bone", asking = listOf("server"))
            .couldNotAnswer("server", "Reading Room")
            .askingAgain("server")
        assertTrue(listing.silent.isEmpty())
        assertEquals(listOf("server"), listing.waiting)
    }

    @Test
    fun `a library that answers after failing loses its notice`() {
        val listing = SearchListing.of("bone", asking = listOf("server"))
            .couldNotAnswer("server", "Reading Room")
            .answered("server", listOf(away("Bone")))
        assertTrue(listing.silent.isEmpty())
        assertEquals(1, listing.rows.size)
    }

    @Test
    fun `two libraries are waited for one at a time`() {
        val start = SearchListing.of(
            "bone",
            local = listOf(held("Bone")),
            asking = listOf("a", "b"),
        )
        val half = start.answered("a", emptyList())
        assertEquals(listOf("b"), half.waiting)
        assertTrue(half.isWaiting)
        assertFalse(half.answered("b", emptyList()).isWaiting)
    }

    @Test
    fun `a row is labelled only when the reader has more than one library`() {
        assertFalse(SearchListing.of("bone").namesOrigin)
        assertTrue(SearchListing.of("bone", namesOrigin = true).namesOrigin)
        // Carried through an answer, so a label cannot appear or vanish mid-search.
        assertTrue(
            SearchListing.of("bone", namesOrigin = true)
                .answered("server", listOf(away("Bone")))
                .namesOrigin,
        )
    }

    @Test
    fun `nothing typed is nothing found`() {
        assertTrue(SearchListing.of("").groups.isEmpty())
    }

    @Test
    fun `a publication whose library is gone reads as being on the device`() {
        val row = FoundRow.held(
            publication("Bone", UUID.randomUUID()),
            MatchKind.PUBLICATION,
            SourceRegistry(sources = emptyList()),
        )
        assertEquals(SearchOrigin.ThisDevice, row.origin)
    }

    @Test
    fun `a publication carries the name its library was given`() {
        val source = Source(displayName = "Attic NAS", kind = SourceKind.LOCAL_FOLDER)
        val rows = FoundRow.held(
            listOf(
                MatchGroup(
                    MatchKind.PUBLICATION,
                    listOf(publication("Bone", source.id)),
                ),
            ),
            SourceRegistry(sources = listOf(source)),
        )
        assertEquals(
            listOf(SearchOrigin.Library(source.id.toString(), "Attic NAS")),
            rows.map { it.origin },
        )
    }
}
