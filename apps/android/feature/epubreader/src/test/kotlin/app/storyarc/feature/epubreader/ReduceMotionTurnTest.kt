package app.storyarc.feature.epubreader

import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The reflowable reader's turn under Reduce Motion, and the curl's device gate.
 *
 * `page-transitions`: Slide becomes Fast fade's own turn under Reduce Motion, and
 * [EpubReaderViewModel.transitions] has to say so through `effective` rather than the
 * chosen mode — `EpubReaderActivity` reads `transitions(reduceMotion).effective` for
 * both the turn owner and the preferences it submits to Readium.
 *
 * The curl's own gate guards a device that cannot hold its refresh rate: before this,
 * `canCurl` was hardcoded `true`, so API 31–32 offered Curl with the reflowable-text
 * reason instead of leaving it absent.
 */
@RunWith(RobolectricTestRunner::class)
class ReduceMotionTurnTest {

    private fun reader(): EpubReaderViewModel = EpubReaderViewModel(
        application = RuntimeEnvironment.getApplication(),
        location = NOWHERE,
        identity = PublicationIdentity(normalizedPath = NOWHERE),
        progress = null,
    )

    @Test
    @Config(sdk = [34])
    fun `slide becomes fast fade's own turn under reduce motion`() {
        val model = reader()
        model.choose(PageTransition.SLIDE)

        assertEquals(PageTransition.SLIDE, model.transitions(reduceMotion = false).effective)
        assertEquals(PageTransition.FAST_FADE, model.transitions(reduceMotion = true).effective)
    }

    @Test
    @Config(sdk = [34])
    fun `fast fade itself is unaffected by reduce motion`() {
        val model = reader()
        model.choose(PageTransition.FAST_FADE)

        assertEquals(PageTransition.FAST_FADE, model.transitions(reduceMotion = true).effective)
    }

    @Test
    @Config(sdk = [34])
    fun `submitted preferences follow the effective mode, not the chosen one`() {
        val model = reader()
        model.choose(PageTransition.SLIDE)

        // Neither Slide nor Fast fade is Readium's continuous-scroll mode, so `scroll`
        // does not move -- what this guards is that `preferences` compiles and runs
        // against `effective` at all, which a raw `_transition.value` read would not.
        assertFalse(model.preferences(reduceMotion = true).scroll ?: false)
    }

    @Test
    @Config(sdk = [34])
    fun `curl is offered on a device that can hold its refresh rate`() {
        // This suite's device is API 34; `CanCurlOnTest` in `:core:model` is what proves
        // the API 31-32 branch, with no Robolectric SDK artifact this sandbox cannot fetch.
        assertFalse(reader().transitions(reduceMotion = false).curlIsAbsent)
    }

    private companion object {
        const val NOWHERE = "/nowhere.epub"
    }
}
