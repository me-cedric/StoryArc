package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * What the About screen has to say, and the one place the support link may appear.
 *
 * `settings-and-about`, *About contents*: the screen "shows the app version and build, the
 * byline, a link to the StoryArc repository, and the licence". *Support link*: it "states
 * that StoryArc is completely free and open source with no paid tier and no advertising, and
 * offers an optional link to <https://ko-fi.com/mecedric>", and that link "is never presented
 * as a prompt, an interstitial, or a nag — it appears only on this screen".
 *
 * `AboutBylineTest` already owns the byline. This suite owns the other five rows, the
 * acknowledgement rows the inventory produces, and the exclusivity clause — which is the one
 * claim no screen test can answer, because it is about every *other* screen. That clause is
 * read from the Android sources instead: the address is written once, in this group.
 *
 * The group is composed rather than read as source, for the reason `AboutBylineTest` gives: a
 * row left behind a comment satisfies a text match and fails a reader. This table has no iOS
 * suite yet.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class AboutContentsTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int): String = context.getString(id)

    /**
     * A version and a build this test chose.
     *
     * Written into the package the app reads from rather than compared against whatever the
     * test manifest happens to hold: a screen that had stopped reading the package would
     * still show the em dash [BuildInfo] falls back to, and an assertion against that dash
     * would pass.
     */
    @Before
    fun aBuildWithAVersion() {
        val info = Shadows.shadowOf(context.packageManager)
            .getInternalMutablePackageInfo(context.packageName)
        info.versionName = VERSION
        info.longVersionCode = BUILD
        BuildInfo.read(context)
    }

    private fun showAbout() {
        compose.setContent { StoryArcTheme { AboutGroup() } }
    }

    @Test
    fun `the screen names the version and the build this app was made from`() {
        showAbout()

        compose.onNodeWithText(VERSION, substring = true).assertIsDisplayed()
        compose.onNodeWithText(BUILD.toString(), substring = true).assertIsDisplayed()
    }

    @Test
    fun `the repository and the licence are rows a reader can press`() {
        showAbout()

        compose.onNodeWithText(string(R.string.about_repository)).assertHasClickAction()
        compose.onNodeWithText(string(R.string.about_licence)).assertHasClickAction()
        compose.onNodeWithText(string(R.string.about_report)).assertHasClickAction()
    }

    @Test
    fun `the screen states that the app costs nothing`() {
        showAbout()

        compose.onNodeWithText(string(R.string.about_free)).assertIsDisplayed()
    }

    @Test
    fun `the support link is offered once, and it is marked optional`() {
        showAbout()

        val support = string(R.string.about_support)
        assertEquals(
            "The support link is drawn ${compose.onAllNodesWithText(support).fetchSemanticsNodes().size}" +
                " times. One screen, one offer.",
            1,
            compose.onAllNodesWithText(support).fetchSemanticsNodes().size,
        )
        compose.onNodeWithText(support).assertHasClickAction()
        // "offers an *optional* link": a reader has to be able to read that off the row
        // itself, because the row is the whole of the ask.
        assertTrue("The support row does not say it is optional: \"$support\"", support.contains("optional"))
    }

    @Test
    fun `every acknowledged component has a row of its own`() {
        val notices = Notices.forAndroid(context.assets).getOrThrow()
        assertTrue("There is nothing to acknowledge — see AcknowledgementsTest.", notices.isNotEmpty())

        showAbout()

        compose.onNodeWithText(string(R.string.about_acknowledgements)).assertExists()
        notices.forEach { notice ->
            // The title exactly, not the name as a substring. One component's reason names
            // another component — SLF4J's reason names smbj, because that is the honest
            // answer to "why is it in the app" — and a substring finder counted that reason
            // as a second row.
            //
            // `onAllNodes`, because several components share one licence identifier and a
            // finder that demands exactly one node would fail on the second Apache row.
            val title = notice.version?.let { "${notice.name} $it" } ?: notice.name
            val row = compose.onAllNodesWithText(title).fetchSemanticsNodes()
            assertEquals("${notice.name} has no row on the screen.", 1, row.size)
            assertTrue(
                "${notice.name}'s row does not name the ${notice.licence} licence it is under.",
                compose.onAllNodesWithText(notice.licence, substring = true)
                    .fetchSemanticsNodes().isNotEmpty(),
            )
        }
    }

    /**
     * A build whose inventory did not decode says so.
     *
     * The screen used to draw the heading, the note, and then nothing — which reads as "this
     * app ships nothing of anyone else's" and is false. The inventory is handed in rather than
     * read, because a Robolectric run opens the real assets and they decode.
     */
    @Test
    fun `an unreadable inventory is stated rather than drawn as an empty list`() {
        compose.setContent {
            StoryArcTheme {
                AboutGroup(notices = Result.failure(IllegalStateException("the staged file is truncated")))
            }
        }

        compose.onNodeWithText(string(R.string.about_acknowledgements)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.about_acknowledgements_unreadable)).assertIsDisplayed()
    }

    /**
     * The support address is written in one file, and it is this group's.
     *
     * The nag clause, which is a claim about every screen that is *not* About. Read from the
     * sources because there is no composition that holds every other screen at once, and the
     * failure it guards — a second call site added somewhere warmer, a launch prompt, a
     * banner over the library — puts the address in a second file before it puts it on a
     * screen.
     */
    @Test
    fun `no other screen in the app knows the support address`() {
        val root = System.getProperty(ROOT_DIRECTORY)?.let(::File)
            ?: error(
                "$ROOT_DIRECTORY is unset. This test reads the app's own sources and will not go" +
                    " looking for them elsewhere — run it through Gradle" +
                    " (`node scripts/gradle.mjs :feature:settings:testDebugUnitTest`), which sets" +
                    " the property from the Android root.",
            )
        val naming = root.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { it.path.contains("/src/main/") && !it.path.contains("/build/") }
            .filter { it.readText().contains(SUPPORT_HOST) }
            .map { it.name }
            .toList()

        assertEquals(
            "The support address is written in $naming. It belongs to About alone, so a second" +
                " file holding it is a prompt, an interstitial or a nag waiting to be drawn.",
            listOf("AboutGroup.kt"),
            naming,
        )
    }

    private companion object {
        /** Set by `:feature:settings`'s build script, for the reason the test above states. */
        const val ROOT_DIRECTORY = "storyarc.android.rootDir"

        /** The address the spec names. Host only, so a query string cannot hide a second use. */
        const val SUPPORT_HOST = "ko-fi.com"

        const val VERSION = "9.9.9"
        const val BUILD = 4242L
    }
}
