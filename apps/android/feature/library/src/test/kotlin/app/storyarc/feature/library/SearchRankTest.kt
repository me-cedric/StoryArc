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
    fun `the fold takes case and accents and nothing else`() {
        // The mirror's tightest joint. iOS's `String.folding(options:)` would give "strasse"
        // and "file" here and Kotlin's `lowercase` cannot, so a fold written the obvious way
        // on each platform would rank a German title differently on the two. iOS's
        // `SearchRankTests` asserts this same table.
        assertEquals("cafe", SearchRank.fold("Café"))
        assertEquals("cafe", SearchRank.fold("CAFÉ"))
        assertEquals("bone", SearchRank.fold("  Bone  "))
        assertEquals("straße", SearchRank.fold("Straße"))
        assertEquals("ﬁle", SearchRank.fold("ﬁle"))
        assertEquals("istanbul", SearchRank.fold("İstanbul"))
    }

    @Test
    fun `a title outside the basic plane is as long on one platform as the other`() {
        // Kotlin counts a UTF-16 unit and Swift a grapheme cluster; both count a code point
        // the same. "Bone 𝔅" is six code points and seven UTF-16 units, so counted the wrong
        // way it ties with "Bone Up" and the two platforms break the tie differently.
        val ordered = SearchRank.ordered(listOf(away("Bone Up"), away("Bone 𝔅")), "bone")
        assertEquals(listOf("Bone 𝔅", "Bone Up"), ordered.map { it.result.title })
    }

    @Test
    fun `blank space around a term is trimmed by a rule not by a platform default`() {
        // `String.trim` keeps the non-breaking spaces and Foundation trims them, so a term
        // pasted out of a web page would otherwise tier differently on the two platforms.
        assertEquals("bone", SearchRank.fold("\u00A0Bone\u00A0"))
        assertEquals("bone", SearchRank.fold("\u202FBone\u2007"))
        assertEquals("bone", SearchRank.fold("\u0085Bone\u2029"))
    }

    @Test
    fun `two titles equal on every other key are ordered by code point not by unit`() {
        // "bone \uFB01" and "bone \uD835\uDD05" are both six code points and both begin
        // with the term, so the last key decides. Kotlin's `compareTo` orders by UTF-16 unit
        // and Swift's `<` by scalar, and a leading surrogate sorts under U+FB01 where the
        // scalar it stands for sorts over it — so the two platforms disagreed here.
        val ordered = SearchRank.ordered(
            listOf(away("bone \uD835\uDD05"), away("bone \uFB01")),
            "bone",
        )
        assertEquals(listOf("bone \uFB01", "bone \uD835\uDD05"), ordered.map { it.result.title })
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
