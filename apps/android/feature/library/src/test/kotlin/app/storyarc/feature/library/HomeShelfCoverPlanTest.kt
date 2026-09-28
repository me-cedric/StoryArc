package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What a Kavita shelf's card draws on the home surface, decided from what the server
 * answered -- the field report's own order: the server's own cover, then the first members',
 * then a named blank.
 */
class HomeShelfCoverPlanTest {

    @Test
    fun `the server's own locked cover wins, whatever else came back`() {
        assertEquals(HomeShelfCoverPlan.Sole, HomeShelfCoverPlan.decide(hasLockedCover = true, memberIds = emptyList()))
        assertEquals(
            HomeShelfCoverPlan.Sole,
            HomeShelfCoverPlan.decide(hasLockedCover = true, memberIds = listOf("1", "2")),
        )
    }

    @Test
    fun `with no locked cover, the first members composite`() {
        assertEquals(
            HomeShelfCoverPlan.Composite(listOf("7", "3", "9", "1")),
            HomeShelfCoverPlan.decide(hasLockedCover = false, memberIds = listOf("7", "3", "9", "1")),
        )
    }

    @Test
    fun `nothing answered at all draws the named blank`() {
        assertEquals(HomeShelfCoverPlan.Blank, HomeShelfCoverPlan.decide(hasLockedCover = false, memberIds = emptyList()))
    }
}
