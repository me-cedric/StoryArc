package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * *Other issues in this series*, in the order the delta asks for.
 *
 * "In volume and chapter order" is two keys, not one, and getting it wrong is not a
 * cosmetic fault: a set of collected editions interleaved with the issues inside them is a
 * shelf a reader cannot use to find the next thing to read.
 */
class PublicationSeriesTest {

    private fun issue(
        title: String,
        series: String? = "Bone",
        number: String? = null,
        volume: Int? = null,
    ) = Publication(
        identity = PublicationIdentity(contentDigest = title),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        number = number,
        volume = volume,
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun issuesRunInNumberOrderAndTenFollowsNine() {
        // String order would put #10 between #1 and #2, which is the classic way a comic
        // shelf ends up unreadable.
        val one = issue("one", number = "1")
        val nine = issue("nine", number = "9")
        val ten = issue("ten", number = "10")

        val rest = restOfSeries(one, listOf(ten, nine, one))

        assertEquals(listOf("nine", "ten"), rest.map { it.displayTitle })
    }

    @Test
    fun aHalfIssueSitsWhereItBelongs() {
        // "3.5" is a real issue number, and the delta's ordering has to hold it.
        val three = issue("three", number = "3")
        val half = issue("half", number = "3.5")
        val four = issue("four", number = "4")

        val rest = restOfSeries(three, listOf(four, half, three))

        assertEquals(listOf("half", "four"), rest.map { it.displayTitle })
    }

    @Test
    fun volumesSortBeforeNumbers() {
        val first = issue("v1 #1", volume = 1, number = "1")
        val second = issue("v2 #1", volume = 2, number = "1")
        val third = issue("v1 #2", volume = 1, number = "2")

        val rest = restOfSeries(first, listOf(second, third, first))

        assertEquals(listOf("v1 #2", "v2 #1"), rest.map { it.displayTitle })
    }

    @Test
    fun aOneOffWithNoNumberSortsLast() {
        val one = issue("one", number = "1")
        val annual = issue("annual")
        val two = issue("two", number = "2")

        val rest = restOfSeries(one, listOf(annual, two, one))

        assertEquals(listOf("two", "annual"), rest.map { it.displayTitle })
    }

    @Test
    fun aPublicationWithNoSeriesHasNoShelf() {
        // The screen draws an absent shelf rather than an empty one, which it can only do
        // if this answers with nothing rather than with everything.
        val loner = issue("loner", series = null)

        assertTrue(restOfSeries(loner, listOf(loner, issue("one", number = "1"))).isEmpty())
    }

    @Test
    fun anotherSeriesIsNotThisOne() {
        val here = issue("bone one", number = "1")
        val elsewhere = issue("akira one", series = "Akira", number = "1")

        val rest = restOfSeries(here, listOf(here, elsewhere))

        assertTrue(rest.isEmpty())
    }

    @Test
    fun thePublicationItselfIsNeverOnItsOwnShelf() {
        val here = issue("bone one", number = "1")
        val next = issue("bone two", number = "2")

        val rest = restOfSeries(here, listOf(here, next, here))

        assertEquals(listOf("bone two"), rest.map { it.displayTitle })
    }
}
