package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * *Other issues in this series*, in the order the delta asks for.
 *
 * "In volume and chapter order" is two keys, not one, and getting it wrong is not a
 * cosmetic fault: a set of collected editions interleaved with the issues inside them is a
 * shelf a reader cannot use to find the next thing to read.
 *
 * And what a cover or a row says about its series, which is the same file's other job.
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

    @Test
    fun aTitleThatAlreadyCarriesTheSeriesAndNumberGetsNoCaption() {
        // The defect this function exists for. `Harbour Lights #1` inside the series
        // `Harbour Lights` differs from its series name, so a bare comparison lets the
        // caption through and the reader is told the title twice.
        val issue = issue("Harbour Lights #1", series = "Harbour Lights", number = "1")

        assertNull(seriesLine(issue))
    }

    @Test
    fun aTitleThatIsTheSeriesStillGainsItsNumber() {
        // The title is the series alone, so the number is a fact the title does not carry
        // and the caption is worth its line. This is the one case where composing before
        // comparing *adds* a caption rather than removing one.
        //
        // iOS asserts the same thing in `SeriesLineTests` under "A composed line that adds
        // the number is shown". The two platforms disagreed here for one rebase — Android
        // returned null on a bare-series early guard, iOS returned the line — which is
        // exactly the silent divergence the mirrored-test rule exists to catch.
        val issue = issue("Harbour Lights", series = "Harbour Lights", number = "1")

        assertEquals("Harbour Lights #1", seriesLine(issue))
    }

    @Test
    fun aTitleThatIsTheSeriesWithNoNumberGetsNoCaption() {
        // Nothing to add, so nothing is said and the caption falls through to the author.
        val issue = issue("Harbour Lights", series = "Harbour Lights")

        assertNull(seriesLine(issue))
    }

    @Test
    fun aSeriesTheTitleDoesNotCarryIsStillNamed() {
        val issue = issue("The Long Way Down", series = "Harbour Lights", number = "4")

        assertEquals("Harbour Lights #4", seriesLine(issue))
    }

    @Test
    fun aSeriesWithNoNumberIsNamedOnItsOwn() {
        val issue = issue("The Long Way Down", series = "Harbour Lights")

        assertEquals("Harbour Lights", seriesLine(issue))
    }

    @Test
    fun aBlankSeriesIsNoSeries() {
        // A blank field is a field the file did not fill in. Left unguarded it captions
        // every affected row with a bare " #4".
        assertNull(seriesLine(issue("The Long Way Down", series = "  ", number = "4")))
        assertNull(seriesLine(issue("The Long Way Down", series = null)))
    }

    @Test
    fun aBlankNumberDoesNotEarnAHash() {
        val issue = issue("The Long Way Down", series = "Harbour Lights", number = " ")

        assertEquals("Harbour Lights", seriesLine(issue))
    }
}
