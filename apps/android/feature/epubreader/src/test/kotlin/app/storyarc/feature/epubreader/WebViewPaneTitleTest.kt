package app.storyarc.feature.epubreader

import android.webkit.WebView
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * D23: the publication's web view is named with the publication title, as its pane title.
 *
 * The scanner reported "UNNAMED WebView" here. A pane title names the page without a
 * `contentDescription`, which TalkBack would read in place of the page's own text.
 * Whether TalkBack still reads the page paragraph by paragraph is a device check.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WebViewPaneTitleTest {

    @Test
    fun `the web view inside the navigator's view takes the title as its pane title`() {
        val context = RuntimeEnvironment.getApplication()
        val webView = WebView(context)
        val page = FrameLayout(context).apply { addView(webView) }
        val root = FrameLayout(context).apply { addView(page) }

        PublicationEgress.namePane(root, "Moby-Dick")

        assertEquals("Moby-Dick", ViewCompat.getAccessibilityPaneTitle(webView)?.toString())
        assertNull("only the web view is a pane", ViewCompat.getAccessibilityPaneTitle(page))
        assertNull("the page text is not replaced by a description", webView.contentDescription)
    }
}
