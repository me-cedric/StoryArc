package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same seven claims iOS's `ListPromotionTests` makes, in the same order. */
class ListPromotionTest {

    /** A list of six, of which the server holds the odd-numbered ones. */
    private val entries = listOf("a", "b", "c", "d", "e", "f")
    private val held = setOf("a", "c", "e")

    private fun promotion(entries: List<String>, held: Set<String>) =
        ListPromotion.of(entries) { it in held }

    @Test
    fun theServerKeepsWhatItAlreadyHas() {
        assertEquals(listOf("a", "c", "e"), promotion(entries, held).copying)
    }

    @Test
    fun whatTheServerLacksIsLeftBehind() {
        // The whole reason the spec asks the app to say which: there is no backend to push a
        // file to, so a publication the server has never seen cannot join one of its lists.
        assertEquals(listOf("b", "d", "f"), promotion(entries, held).leftBehind)
    }

    @Test
    fun theListsOrderSurvives() {
        // The order is a reading list's whole meaning, so a copy that arrived in some other
        // order would be a different list.
        val reversed = promotion(entries.reversed(), held)
        assertEquals(listOf("e", "c", "a"), reversed.copying)
        assertEquals(listOf("f", "d", "b"), reversed.leftBehind)
    }

    @Test
    fun theTotalCountsEverything() {
        val promotion = promotion(entries, held)
        assertEquals(6, promotion.total)
        assertEquals(promotion.copying.size + promotion.leftBehind.size, promotion.total)
    }

    @Test
    fun aServerThatHoldsNoneOfItCannotTakeIt() {
        val promotion = promotion(entries, emptySet())
        assertFalse(promotion.isPossible)
        assertEquals(entries, promotion.leftBehind)
    }

    @Test
    fun anEmptyListPromotesNothing() {
        val promotion = promotion(emptyList(), held)
        assertFalse(promotion.isPossible)
        assertEquals(0, promotion.total)
        assertTrue(promotion.leftBehind.isEmpty())
    }

    @Test
    fun aFullyHeldListLeavesNothingBehind() {
        val promotion = promotion(listOf("a", "c"), held)
        assertTrue(promotion.isPossible)
        assertEquals(listOf("a", "c"), promotion.copying)
        assertTrue(promotion.leftBehind.isEmpty())
    }
}
