package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The privacy posture is on the screen, and each kind of data says what clearing it frees.
 *
 * `settings-and-about`, *Privacy screen*: the section "states that StoryArc has no account, no
 * backend, no analytics, and no crash reporting, and that data leaves the device only to the
 * sources the user configured". *Clearing data*: "cache, reading history, and downloads are
 * individually clearable, each stating what it removes and how much space it frees".
 *
 * The size is the half that rots quietly. A row that stopped measuring would still draw, still
 * say Clear and still be pressable — it would only stop saying how much, which is the one thing
 * that tells a reader whether pressing it is worth anything. So the cache is given real bytes
 * and the downloads a real total, and each row is read back.
 *
 * `ClearCacheTest` owns what `clearCache` deletes. This suite owns what the screen says.
 * This table has no iOS suite yet.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class PrivacyScreenTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int, vararg arguments: Any): String = context.getString(id, *arguments)

    private fun showPrivacy(downloadedBytes: Long = 0L) {
        compose.setContent {
            StoryArcTheme { PrivacyGroup(downloadedBytes = downloadedBytes) }
        }
    }

    /** Puts [bytes] of nothing in the cache directory, so the cache row has something to say. */
    private fun fillCache(bytes: Int) {
        File(context.cacheDir, "page.bin").writeBytes(ByteArray(bytes))
    }

    /** The whole text of the one row that starts with [prefix]. */
    private fun row(prefix: String): String {
        val nodes = compose.onAllNodesWithText(prefix, substring = true).fetchSemanticsNodes()
        assertEquals("Expected one row starting \"$prefix\", found ${nodes.size}.", 1, nodes.size)
        return nodes.single().config[SemanticsProperties.Text].joinToString("") { it.text }
    }

    @Test
    fun `the screen states the four things the app does not have`() {
        val statement = string(R.string.privacy_statement)
        // The posture itself, not only that a sentence is drawn: a rewrite that dropped one
        // of the four would leave the screen looking exactly as it does now.
        listOf("account", "backend", "analytics", "crash").forEach { absence ->
            assertTrue("The statement does not mention $absence: \"$statement\"", statement.contains(absence))
        }

        showPrivacy()

        compose.onNodeWithText(statement).assertIsDisplayed()
    }

    @Test
    fun `the screen states that data goes only where the reader sent it`() {
        showPrivacy()

        compose.onNodeWithText(string(R.string.privacy_sources)).assertIsDisplayed()
    }

    @Test
    fun `each of the three kinds of data says what clearing it removes`() {
        showPrivacy()

        // The note under each title is the "what it removes" half.
        compose.onNodeWithText(string(R.string.privacy_cache_note)).assertExists()
        compose.onNodeWithText(string(R.string.privacy_history_note)).assertExists()
        compose.onNodeWithText(string(R.string.privacy_downloads_note)).assertExists()
    }

    @Test
    fun `each kind has a clear of its own, told apart by name`() {
        fillCache(bytes = 4_096)
        showPrivacy(downloadedBytes = 1_024)

        // Three visible labels all read "Clear", so the accessible names are what a reader
        // without sight has to tell them apart by — and what proves there are three actions
        // rather than one.
        compose.onNodeWithContentDescription(string(R.string.privacy_clear_cache)).assertIsEnabled()
        compose.onNodeWithContentDescription(string(R.string.privacy_clear_history)).assertExists()
        compose.onNodeWithContentDescription(string(R.string.privacy_clear_downloads)).assertIsEnabled()
    }

    @Test
    fun `the cache row states how much space clearing it would free`() {
        fillCache(bytes = 64 * 1024)
        showPrivacy()

        val title = row(string(R.string.privacy_cache, "").trimEnd())
        val size = title.substringAfter(string(R.string.privacy_cache, "").trimEnd()).trim()
        assertTrue("The cache row states no size: \"$title\"", size.isNotEmpty())
        assertTrue("The cache row states \"$size\", which frees nothing.", size.first().isDigit())
        assertTrue("The cache row states \"$size\" for 64 kB of files.", size.startsWith("64"))
    }

    @Test
    fun `the downloads row states the figure the rest of the app states`() {
        val bytes = 5_242_880L
        showPrivacy(downloadedBytes = bytes)

        val title = row(string(R.string.privacy_downloads, "").trimEnd())
        // The platform formatter, which is what the Downloads group and the settings summary
        // show. One number rendered two ways in one app reads as two numbers.
        val expected = android.text.format.Formatter.formatShortFileSize(context, bytes)
        assertTrue("The downloads row reads \"$title\" rather than \"$expected\".", title.endsWith(expected))
    }

    @Test
    fun `a row with nothing to free cannot be pressed`() {
        showPrivacy(downloadedBytes = 0L)

        // The other half of stating a size: zero is a real answer, and a Clear that does
        // nothing teaches a reader that the number beside it means nothing either.
        compose.onNodeWithContentDescription(string(R.string.privacy_clear_downloads)).assertIsNotEnabled()
    }
}
