package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same six claims iOS's `CompositeCoverTests` makes. */
class CompositeCoverTest {

    private fun collection(members: Set<String>, cover: String? = null) =
        PublicationCollection(name = "Image Comics", members = members, coverMemberId = cover)

    @Test
    fun aCollectionWithNothingInItHasNothingToComposite() {
        assertTrue(CompositeCover.tiles(collection(emptySet())).isEmpty())
    }

    @Test
    fun oneTwoOrThreeMembersShowOneCoverRatherThanAQuadrantWithHoles() {
        assertEquals(listOf("b"), CompositeCover.tiles(collection(setOf("b"))))
        assertEquals(listOf("a"), CompositeCover.tiles(collection(setOf("b", "a"))))
        assertEquals(listOf("a"), CompositeCover.tiles(collection(setOf("c", "a", "b"))))
    }

    @Test
    fun fourMembersAreTheFourTilesByIdentityAscending() {
        val tiles = CompositeCover.tiles(collection(setOf("d", "b", "a", "c")))
        assertEquals(listOf("a", "b", "c", "d"), tiles)
    }

    @Test
    fun aFifthMemberChangesNothingTheFirstFourAreTheComposite() {
        val tiles = CompositeCover.tiles(collection(setOf("e", "d", "c", "b", "a")))
        assertEquals(listOf("a", "b", "c", "d"), tiles)
        assertEquals(CompositeCover.TILE_COUNT, tiles.size)
    }

    @Test
    fun aCoverTheReaderChoseReplacesTheCompositeOutright() {
        val chosen = collection(setOf("a", "b", "c", "d", "e"), cover = "e")
        assertEquals(listOf("e"), CompositeCover.tiles(chosen))
    }

    @Test
    fun aChosenCoverThatHasLeftTheCollectionIsNotItsCoverAnyMore() {
        val stale = collection(setOf("a", "b", "c", "d"), cover = "z")
        assertEquals(listOf("a", "b", "c", "d"), CompositeCover.tiles(stale))
    }
}
