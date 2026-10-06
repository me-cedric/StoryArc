package app.storyarc.core.persistence

import app.storyarc.core.model.CurlVerdict
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.TransitionChoices
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a device judges its own curl, and that a slow one withholds it without losing the
 * reader's choice.
 *
 * `page-transitions`: Curl is absent where the device "cannot render it at the display's
 * refresh rate", and "a user who set Curl on a capable device and later opens the library on
 * this one reads with Slide without their stored preference being overwritten". Until D11
 * nothing measured the first half, so no device had ever withheld Curl for the refresh rate.
 *
 * **No case below states a frame rate.** A strain is a ratio of what a turn cost to what the
 * panel allowed for it, so every number here is dimensionless and none can be misread as a
 * claim about a phone. iOS's `CurlCapabilityTests` asserts the same table.
 */
class CurlCapabilityTest {

    private fun fresh() = CurlCapability(FakePreferences())

    @Test
    fun `a device is given the curl until it has failed, not until it has passed`() {
        val capability = fresh()
        assertTrue(capability.isUnjudged)
        assertFalse(capability.cannotCurl)

        // Two bad turns are not an answer either: the third is what decides, and a reader
        // who has curled twice on a new phone is still curling.
        capability.record(3.0)
        capability.record(3.0)
        assertTrue(capability.isUnjudged)
        assertFalse(capability.cannotCurl)
    }

    @Test
    fun `three turns that miss a third of their frames withhold the curl`() {
        val capability = fresh()
        repeat(CurlVerdict.TURNS) { capability.record(2.0) }
        assertFalse(capability.isUnjudged)
        assertTrue("A device that misses a third of its frames is still offered Curl.", capability.cannotCurl)
    }

    @Test
    fun `three turns that keep up leave the curl alone, for good`() {
        val capability = fresh()
        repeat(CurlVerdict.TURNS) { capability.record(1.0) }
        assertFalse(capability.isUnjudged)
        assertFalse(capability.cannotCurl)
        // And the instrument stops: a judged device pays for no more frame clocks.
        capability.record(9.0)
        assertFalse(capability.cannotCurl)
    }

    @Test
    fun `one cold first turn does not condemn a device that draws the rest perfectly`() {
        // The reason for a median rather than a mean. A first curl that costs three times its
        // budget, then two that cost nothing extra: the mean is 1.67 and fails, the median is
        // 1 and passes.
        val capability = fresh()
        for (strain in listOf(3.0, 1.0, 1.0)) capability.record(strain)
        assertFalse(capability.cannotCurl)
    }

    @Test
    fun `what a device showed survives the next launch`() {
        val preferences = FakePreferences()
        repeat(CurlVerdict.TURNS) { CurlCapability(preferences).record(2.0) }
        assertTrue("The verdict did not survive the launch.", CurlCapability(preferences).cannotCurl)

        CurlCapability(preferences).reset()
        assertTrue(CurlCapability(preferences).isUnjudged)
    }

    @Test
    fun `a device that cannot curl keeps the reader's stored Curl`() {
        // The half of the scenario that is about the reader rather than the device. The
        // verdict reaches `TransitionChoices` as `canCurl`, and nothing writes `chosen`.
        val choices = TransitionChoices(
            chosen = PageTransition.PAGE_CURL,
            axis = ScrollAxis.VERTICAL,
            reduceMotion = false,
            canCurl = false,
        )
        assertEquals(PageTransition.PAGE_CURL, choices.chosen)
        assertEquals(PageTransition.SLIDE, choices.effective)
        assertTrue(choices.curlIsAbsent)
    }
}
