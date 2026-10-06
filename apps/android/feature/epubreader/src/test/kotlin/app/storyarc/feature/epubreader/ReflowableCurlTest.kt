package app.storyarc.feature.epubreader

import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * That a page of prose can curl, which is task 8.12 and closes
 * `reader-theming-and-page-transitions` 4.3b.
 *
 * Three things have to hold together, and each is asserted on its own below: the mode is
 * offered over reflowable content at all, the reflowable reader claims the turn when it is
 * chosen, and the turn it claims is the roll rather than the dip.
 *
 * **What is not here is the roll.** It is an AGSL shader filling a rectangle in a [CurlSheet],
 * and Robolectric has no GPU in it — `PageCurlShaderTests` is the tripwire on the shader's
 * text and `docs/designs/screenshots/` holds the frame. iOS asserts the same rules in
 * `ReflowableCurlTests`.
 */
@RunWith(RobolectricTestRunner::class)
class ReflowableCurlTest {

    private fun reader(): EpubReaderViewModel = EpubReaderViewModel(
        application = RuntimeEnvironment.getApplication(),
        location = NOWHERE,
        identity = PublicationIdentity(normalizedPath = NOWHERE),
        progress = null,
    )

    @Test
    @Config(sdk = [34])
    fun `a reflowable book offers the curl, and does not name it unavailable`() {
        val choices = reader().transitions(reduceMotion = false)

        assertTrue(PageTransition.PAGE_CURL in choices.offered)
        assertNull(choices.unavailable[PageTransition.PAGE_CURL])
    }

    @Test
    @Config(sdk = [34])
    fun `the turn curl claims is the roll, and the turn fast fade claims is the dip`() {
        // One funnel, `EpubPageTurns.turn`, reads this. A mode that answered FAST_FADE here
        // would dip through the page colour under a reader who chose the curl.
        val model = reader()

        model.choose(PageTransition.PAGE_CURL)
        assertEquals(PageTransition.PAGE_CURL, model.transitions(reduceMotion = false).drawnTurn)

        model.choose(PageTransition.FAST_FADE)
        assertEquals(PageTransition.FAST_FADE, model.transitions(reduceMotion = false).drawnTurn)

        model.choose(PageTransition.SLIDE)
        assertNull(model.transitions(reduceMotion = false).drawnTurn)

        model.choose(PageTransition.VERTICAL_SCROLL)
        assertNull(model.transitions(reduceMotion = false).drawnTurn)
    }

    @Test
    @Config(sdk = [34])
    fun `reduce motion still replaces the curl with the fade`() {
        // `page-transitions`: "Curl and Slide are replaced by Fast fade". Offering the curl
        // over text must not reach around that substitution.
        val model = reader()
        model.choose(PageTransition.PAGE_CURL)

        assertEquals(PageTransition.FAST_FADE, model.transitions(reduceMotion = true).drawnTurn)
    }

    @Test
    @Config(sdk = [32])
    fun `a device below the shader's own floor is offered no curl at all`() {
        // Task 9.4's gate, which this must not reach around: AGSL's `RuntimeShader` arrives
        // at API 33, so below it the row is absent rather than listed with a reason.
        val choices = reader().transitions(reduceMotion = false)

        assertTrue(PageTransition.PAGE_CURL !in choices.offered)
        assertEquals(PageTransition.SLIDE, choices.effective)
    }

    private companion object {
        // Nothing is opened: `transitions` answers from the chosen mode and the device, and
        // a path that resolves to nothing is what the reader holds before a book is parsed.
        const val NOWHERE = "/nowhere.epub"
    }
}
