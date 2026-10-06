package app.storyarc.feature.library

import android.content.Intent
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 4.2: the app reads nothing from the browser it hands a reader to.
 *
 * Two halves, because one alone would pass for the wrong reason. The first reads the
 * hand-off's own intent and finds no channel a picture could come back through. The second
 * reads the source and finds no web view, no script and no capture -- which is the edit a
 * later change would make, and the edit that would turn this feature into the thing App
 * Store guideline 5.2.3 and Google's own terms forbid.
 *
 * iOS's `CoverSearchHandoffTests` makes the same four claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CoverSearchHandoffTest {

    /**
     * The feature's own sources, found from the module's own directory.
     *
     * A unit test runs with the module as its working directory, so the source tree is
     * beside it. A guard that cannot find what it guards passes for ever, which is why the
     * read below fails loudly rather than skipping.
     */
    private fun code(name: String): String {
        val file = File("src/main/kotlin/app/storyarc/feature/library/$name")
        assertTrue(
            "${file.absolutePath} could not be read -- has $name moved?",
            file.isFile,
        )
        return file.readLines()
            .joinToString("\n") { if (it.trim().startsWith("//") || it.trim().startsWith("*")) "" else it }
    }

    @Test
    fun `the hand-off opens the address and receives nothing`() {
        // The intent carries an action and a address. There is no result, no callback and no
        // extra an image, a page or an address-the-reader-ended-on could come back in.
        val intent = CoverSearchHandoff.intent("Fine Print", "Ada")!!

        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertTrue(intent.data.toString().contains("duckduckgo.com"))
        assertTrue(intent.data.toString().contains("Fine+Print"))
        // The Custom Tabs protocol's own extra: a supporting browser renders a tab rather
        // than a window, and nothing is sent with it.
        assertTrue(intent.hasExtra(CoverSearchHandoff.SESSION_EXTRA))
        assertNull(intent.getBundleExtra(CoverSearchHandoff.SESSION_EXTRA))
    }

    @Test
    fun `no title means no hand-off`() {
        assertNull(CoverSearchHandoff.intent(" "))
    }

    @Test
    fun `the hand-off is a Custom Tab, never a web view this app owns`() {
        // `design.md` records the reason at length: an in-app web view that captures an
        // image is StoryArc performing the save guideline 5.2.3 forbids, and StoryArc's one
        // web view denies all network egress, so a second one with the opposite rule would
        // quietly undo that property.
        val code = code("CoverSearchHandoff.kt")

        assertTrue(code.contains("Intent.ACTION_VIEW"))
        for (forbidden in listOf("WebView", "WebViewClient", "AndroidView(")) {
            assertTrue(
                "$forbidden is in the hand-off. The whole point of the hand-off is that it is not one.",
                !code.contains(forbidden),
            )
        }
    }

    @Test
    fun `nothing in the hand-off captures, injects or reads the page`() {
        val code = code("CoverSearchHandoff.kt")

        for (
            forbidden in listOf(
                "evaluateJavascript",
                "addJavascriptInterface",
                "startActivityForResult",
                "PixelCopy",
                "drawToBitmap",
            )
        ) {
            assertTrue(
                "$forbidden is a way back from the browser into the app, and there is to be none.",
                !code.contains(forbidden),
            )
        }
    }
}
