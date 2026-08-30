package app.storyarc.feature.epubreader

import android.app.Application
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * The way back from a jump.
 *
 * `ebook-reader`'s "Returning from any jump" is three rules in one scenario: the control is
 * offered after a long jump, it is offered *until it is used or another jump replaces it*,
 * and "using it does not itself become somewhere to return from". None of the three is
 * visible in the pixels — a control that never went away and a control that re-armed itself
 * look identical on the page they left the reader on — so they are asserted here.
 *
 * Instrumented rather than a JVM unit test, for the reason [TableOfContentsTest] gives:
 * Readium's `Url` is built on `android.net.Uri`, which the unit-test android.jar stubs, so
 * every locator here would be a stub answering with defaults. The method names are camelCase
 * for the same reason too — dex refuses a method name holding a space.
 *
 * No publication is opened. What is under test is which position is written down and when it
 * is cleared. iOS's `ReturnPointTests` makes the same five assertions in the same order.
 */
class ReturnPointTest {

    private val application =
        InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application

    private fun model(): EpubReaderViewModel = EpubReaderViewModel(
        application = application,
        location = "/nowhere.epub",
        identity = PublicationIdentity(normalizedPath = "/nowhere.epub"),
        progress = null,
    )

    private fun locator(href: String): Locator =
        Locator(href = Url(href)!!, mediaType = MediaType.XHTML)

    /**
     * Puts the reader somewhere, the way the navigator does.
     *
     * [EpubReaderViewModel.follow] is the only thing that tells the model where the reader
     * is, and it collects on `Dispatchers.Main.immediate` — so this has to run on the main
     * thread for the collection to have happened by the time it returns.
     */
    private fun EpubReaderViewModel.readingAt(href: String) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            follow(MutableStateFlow(locator(href)))
        }
    }

    @Test
    fun aJumpRemembersWhereTheReaderWas() {
        val model = model()
        model.readingAt("OEBPS/ch1.xhtml")

        model.markReturnPoint()

        val point = model.returnPoint.value
        assertNotNull(point)
        assertTrue(point!!.contains("ch1.xhtml"))
    }

    @Test
    fun withNowhereRecordedNothingIsOffered() {
        val model = model()

        model.markReturnPoint()

        // A book that has not reported a position yet. The control is absent rather than
        // present and refusing, which is the same rule the read-aloud button follows.
        assertNull(model.returnPoint.value)
    }

    @Test
    fun aSecondJumpReplacesTheFirstRatherThanStacking() {
        val model = model()
        model.readingAt("OEBPS/ch1.xhtml")
        model.markReturnPoint()

        model.readingAt("OEBPS/ch9.xhtml")
        model.markReturnPoint()

        // One point, not a stack. The control answers "take me back", and a reader who has
        // followed four links in a row means where they were reading, not the third link.
        val point = model.returnPoint.value
        assertNotNull(point)
        assertTrue(point!!.contains("ch9.xhtml"))
    }

    @Test
    fun thePointIsTakenOnceSoTheControlGoesAway() {
        val model = model()
        model.readingAt("OEBPS/ch1.xhtml")
        model.markReturnPoint()

        assertNotNull(model.takeReturnPoint())

        assertNull(model.returnPoint.value)
        assertNull(model.takeReturnPoint())
    }

    @Test
    fun returningDoesNotItselfBecomeSomewhereToReturnFrom() {
        val model = model()
        model.readingAt("OEBPS/ch9.xhtml")
        model.markReturnPoint()
        model.takeReturnPoint()

        // The move the return itself makes. `goToLocator(remember = false)` is what carries
        // it, so nothing marks a point on the way back and a reader is never handed a button
        // that bounces them between two pages for ever.
        model.readingAt("OEBPS/ch1.xhtml")

        assertNull(model.returnPoint.value)
    }
}
