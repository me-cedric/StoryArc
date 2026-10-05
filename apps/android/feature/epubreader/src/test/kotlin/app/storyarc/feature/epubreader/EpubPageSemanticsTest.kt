package app.storyarc.feature.epubreader

import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.ChapterRemainder
import app.storyarc.core.model.ReadingPositionLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * That the reflowable reader names its page turns and says where a turn landed.
 *
 * `native-experience`, *Screen reader*: "the reader announces the page number and total on
 * each turn, and offers gestures to turn pages". The page is a web view, so a screen reader
 * walked its paragraphs and was offered nothing that turned a page, and no turn said
 * afterwards where the reader had arrived.
 *
 * The last test is a tripwire over [EpubReaderActivity]'s own source: the two halves are
 * correct and useless unless the activity installs them, and composing the activity needs a
 * publication and a Readium navigator this gate has not got.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EpubPageSemanticsTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private val page = WebView(context)

    private val root = FrameLayout(context).apply { addView(page) }

    private var turned = 0

    private fun actions(): List<AccessibilityNodeInfoCompat.AccessibilityActionCompat> =
        AccessibilityNodeInfoCompat.wrap(page.createAccessibilityNodeInfo()!!).actionList

    @Test
    fun `the page offers a next-page and a previous-page action, by name`() {
        EpubPageSemantics.install(root) { forward -> turned += if (forward) 1 else -1 }

        assertEquals(
            listOf("Next page", "Previous page"),
            actions().mapNotNull { it.label?.toString() },
        )
    }

    @Test
    fun `each action turns the page it names`() {
        EpubPageSemantics.install(root) { forward -> turned += if (forward) 1 else -1 }
        val named = actions().filter { it.label != null }

        assertTrue("The next-page action refused the turn", page.performAccessibilityAction(named[0].id, null))
        assertEquals(1, turned)
        assertTrue("The previous-page action refused the turn", page.performAccessibilityAction(named[1].id, null))
        assertEquals(0, turned)
    }

    @Test
    fun `a second install adds no duplicate, so one page fragment per resource stays two actions`() {
        EpubPageSemantics.install(root) { }
        EpubPageSemantics.install(root) { }

        assertEquals(2, actions().count { it.label != null })
    }

    @Test
    fun `the position lands as a polite live region, so a turn announces it whatever made it`() {
        EpubPageSemantics.announce(root, "42% read · Chapter Three, about half left")

        assertEquals(View.ACCESSIBILITY_LIVE_REGION_POLITE, root.accessibilityLiveRegion)
        assertEquals("42% read · Chapter Three, about half left", root.stateDescription)
    }

    @Test
    fun `the announced sentence is the menu's own`() {
        val position = ReadingPositionLine(
            percentThrough = 42,
            chapter = "Chapter Three",
            chapterRemainder = ChapterRemainder.ABOUT_HALF_LEFT,
        )

        assertEquals(
            "42% read · Chapter Three, about half left",
            context.readingPositionSentence(position),
        )
    }

    @Test
    fun `the activity installs the actions and follows the position`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val source = File(module, ACTIVITY).readText()

        assertTrue(
            "`EpubReaderActivity` installs no page-turn action on the publication's web view." +
                " Without it a screen reader walks the page and is offered no way to turn it," +
                " which `native-experience`'s screen-reader scenario forbids.",
            source.contains("EpubPageSemantics.install("),
        )
        assertTrue(
            "`EpubReaderActivity` follows the navigator without announcing. `followAndAnnounce`" +
                " is what says where a turn arrived, and it replaces the bare `model.follow`" +
                " precisely so a turn by any means announces.",
            source.contains("followAndAnnounce(navigator.currentLocator)") &&
                !source.contains("model.follow(navigator.currentLocator)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val ACTIVITY = "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
    }
}
