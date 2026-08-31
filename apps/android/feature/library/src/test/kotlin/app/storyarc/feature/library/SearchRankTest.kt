package app.storyarc.feature.library

import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.SearchResult
import app.storyarc.core.model.SearchRoute
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * How one answer is ordered, asserted against the same table as iOS's `SearchRankTests`.
 *
 * `library-browsing` asks for "one ranked list". These are the cases that say what ranked
 * means, including the one the whole design turns on: a remote row that answers better than a
 * local row is above it, and where they answer equally the local one wins.
 *
 * Case for case on both platforms, per ADR-0001. Add a case here, add it there.
 */
class SearchRankTest {

    private fun held(title: String, kind: MatchKind = MatchKind.PUBLICATION) = FoundRow(
        SearchResult(kind = kind, title = title, publicationId = title),
        SearchOrigin.ThisDevice,
    )

    private fun away(
        title: String,
        kind: MatchKind = MatchKind.PUBLICATION,
        from: String = "server",
    ) = FoundRow(
        SearchResult(kind = kind, title = title, route = SearchRoute(from, title)),
        SearchOrigin.Library(from, from),
    )

    private fun strength(title: String, term: String = "bone") =
        SearchRank.strength(SearchRank.fold(title), SearchRank.fold(term))

    @Test
    fun `the five tiers from the title that is the term to the title that is not in it`() {
        assertEquals(SearchRank.Strength.EXACT, strength("Bone"))
        assertEquals(SearchRank.Strength.START, strength("Bone Companion"))
        assertEquals(SearchRank.Strength.WORD, strength("The Bone Orchard"))
        assertEquals(SearchRank.Strength.WITHIN, strength("Carbone"))
        assertEquals(SearchRank.Strength.ELSEWHERE, strength("Ada Lovelace"))
    }

    @Test
    fun `case and accents are not part of the question`() {
        assertEquals(SearchRank.Strength.START, strength("Café Noir", "cafe"))
        assertEquals(SearchRank.Strength.EXACT, strength("CAFÉ", "café"))
        assertEquals(SearchRank.Strength.EXACT, strength("Élan", "elan"))
    }

    @Test
    fun `a word begins after punctuation as well as after a space`() {
        assertEquals(SearchRank.Strength.WORD, strength("Vol.2 Bone", "2"))
        assertEquals(SearchRank.Strength.WORD, strength("d’Artagnan", "artagnan"))
    }

    @Test
    fun `a server's better match outranks the device's worse one`() {
        val ordered = SearchRank.ordered(listOf(held("Carbone"), away("Bone")), "bone")
        assertEquals(listOf("Bone", "Carbone"), ordered.map { it.result.title })
    }

    @Test
    fun `where two rows answer equally well the one that opens now wins`() {
        val ordered = SearchRank.ordered(listOf(away("Bone"), held("Bone")), "bone")
        assertEquals(
            listOf(SearchOrigin.ThisDevice, SearchOrigin.Library("server", "server")),
            ordered.map { it.origin },
        )
    }

    @Test
    fun `at equal strength the shorter title is the fuller answer`() {
        val ordered = SearchRank.ordered(
            listOf(away("Bone Companion"), away("Bone Up")),
            "bone",
        )
        assertEquals(listOf("Bone Up", "Bone Companion"), ordered.map { it.result.title })
    }

    @Test
    fun `rows equal on every other key still have one fixed order`() {
        val ordered = SearchRank.ordered(listOf(away("Bone Bb"), away("Bone Aa")), "bone")
        assertEquals(listOf("Bone Aa", "Bone Bb"), ordered.map { it.result.title })
    }

    @Test
    fun `the heading a row sits under is not a ranking key`() {
        // A series that is the term is above a title that merely contains it, and the two land
        // under different headings — which `SearchListing.groups` decides, not this.
        val ordered = SearchRank.ordered(
            listOf(
                away("Carbone", MatchKind.PUBLICATION),
                away("Bone", MatchKind.SERIES),
            ),
            "bone",
        )
        assertEquals(
            listOf(MatchKind.SERIES, MatchKind.PUBLICATION),
            ordered.map { it.result.kind },
        )
    }

    @Test
    fun `an empty term ranks nothing above anything`() {
        val ordered = SearchRank.ordered(listOf(away("Bb"), held("Aa")), "")
        assertEquals(listOf("Aa", "Bb"), ordered.map { it.result.title })
    }
}
