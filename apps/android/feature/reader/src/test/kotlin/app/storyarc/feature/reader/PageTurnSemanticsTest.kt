package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * That the comic reader names its page turns and says where the turn landed.
 *
 * `native-experience`, *Screen reader*: "the reader announces the page number and total on
 * each turn, and offers gestures to turn pages". The pager offered the system's scroll
 * actions, which name a direction rather than a page, Fast fade offered none at all, and no
 * turn was ever announced.
 *
 * The first three tests compose the modifier and read the semantics back, which is the only
 * way to see what a screen reader is offered. The last one is a tripwire over
 * [ReaderScreen]'s own source: the modifier is correct and useless unless every mode's
 * container takes it, and composing the whole reader needs a publication this gate has not
 * got.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h2400dp")
class PageTurnSemanticsTest {

    @get:Rule
    val compose = createComposeRule()

    private var turned = 0

    private fun page(number: Int = 3, count: Int = 20) {
        compose.setContent {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pageTurnSemantics(
                        page = number,
                        count = count,
                        onNext = { turned += 1 },
                        onPrevious = { turned -= 1 },
                    ),
            )
        }
    }

    private fun actions(): List<CustomAccessibilityAction> = compose
        .onNode(SemanticsMatcher("carries custom actions") { it.config.getOrNull(SemanticsActions.CustomActions) != null })
        .fetchSemanticsNode()
        .config[SemanticsActions.CustomActions]

    @Test
    fun `the page surface offers a next-page and a previous-page action, by name`() {
        page()

        assertEquals(listOf("Next page", "Previous page"), actions().map { it.label })
    }

    @Test
    fun `each action turns the page it names`() {
        page()

        assertTrue("The next-page action refused the turn", actions()[0].action())
        assertEquals(1, turned)
        assertTrue("The previous-page action refused the turn", actions()[1].action())
        assertEquals(0, turned)
    }

    @Test
    fun `the position is a polite live region, so every turn announces it`() {
        page(number = 3, count = 20)

        val node = compose
            .onNode(SemanticsMatcher("carries a state description") { it.config.getOrNull(SemanticsProperties.StateDescription) != null })
            .fetchSemanticsNode()

        assertEquals("Page 3 of 20", node.config[SemanticsProperties.StateDescription])
        assertEquals(LiveRegionMode.Polite, node.config[SemanticsProperties.LiveRegion])
    }

    @Test
    fun `every page mode takes the modifier, Fast fade included`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val source = readerScreenSource(module)

        assertTrue(
            "`ReaderScreen` builds no page surface with `pageTurnSemantics`. Without it the" +
                " reader offers no named page turn and announces no position after a turn," +
                " which is what `native-experience`'s screen-reader scenario asks for.",
            source.contains(".pageTurnSemantics("),
        )
        assertTrue(
            "`pageTurnSemantics` is not on the modifier every mode's container takes. Slide," +
                " Curl, Fast fade and both scrolls share `keyboard`, and a mode that does not" +
                " take it is a mode with no page-turn action — which is how Fast fade came to" +
                " have none.",
            Regex("""val keyboard = Modifier(\n\s+\.\w+\([^\n]*\)?)*?\n\s+\.pageTurnSemantics\(""")
                .containsMatchIn(source),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
