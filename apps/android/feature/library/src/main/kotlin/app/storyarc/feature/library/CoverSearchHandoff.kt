package app.storyarc.feature.library

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import app.storyarc.core.model.CoverWebSearch

/**
 * The Custom Tab a reader is handed to, built as an intent and nothing more.
 *
 * **A Custom Tab, never a `WebView`.** `design.md` records the reason at length and it is
 * two reasons:
 *
 * - App Store Review Guideline 5.2.3, which Google's terms echo, bans saving media from a
 *   third-party source without that source's authorization. A web view this app owns,
 *   capturing an image by screenshot or by reading an element's `src`, is StoryArc
 *   performing that save. The browser performing it is the reader using their browser.
 * - StoryArc's only web view today, the EPUB reader, denies all network egress through
 *   `PublicationEgress`. A second web view that exists to load a search engine would be the
 *   opposite rule on the same app, and two rules about one primitive is how a security
 *   property quietly stops being true.
 *
 * **Built by hand rather than with `androidx.browser`.** The session extra below *is* the
 * Custom Tabs protocol -- a supporting browser reads it and renders a tab rather than a
 * window -- and the library adds a dependency for a builder this screen does not need. The
 * intent carries no callback and no result, so there is no channel a page or a picture could
 * come back through. The only route in is the system picker.
 */
internal object CoverSearchHandoff {
    /**
     * The extra that makes a supporting browser render a Custom Tab.
     *
     * The protocol's own name, which `androidx.browser` sends under the same key. A browser
     * that does not support Custom Tabs ignores it and opens an ordinary tab, which is the
     * same hand-off with a different chrome.
     */
    internal const val SESSION_EXTRA = "android.support.customtabs.extra.SESSION"

    /**
     * What to start for this publication, or null when there is no title to search for.
     *
     * `ACTION_VIEW` and nothing else. Deliberately not `startActivityForResult`: a result is
     * a channel back from the browser, and this feature must have none.
     */
    fun intent(title: String, author: String? = null): Intent? {
        val address = CoverWebSearch.url(title, author) ?: return null
        return Intent(Intent.ACTION_VIEW, Uri.parse(address)).apply {
            putExtra(SESSION_EXTRA, null as Bundle?)
        }
    }
}
