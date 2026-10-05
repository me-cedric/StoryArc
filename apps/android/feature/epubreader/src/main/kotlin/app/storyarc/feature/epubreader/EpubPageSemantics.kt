package app.storyarc.feature.epubreader

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.core.view.ViewCompat
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.model.ReadingPositionLine
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

/**
 * A named page turn on the book itself, and the position the reader lands on.
 *
 * `native-experience`, *Screen reader*: "the reader announces the page number and total on
 * each turn, and offers gestures to turn pages". This reader did neither. The page is a web
 * view, so TalkBack moved through its paragraphs and offered nothing that turned a page, and
 * no turn — by a tap zone, an arrow key, a game controller, a volume button, a swipe, or
 * Fast fade — said afterwards where the reader had arrived.
 *
 * Both halves are here rather than in [EpubReaderActivity] because that file is at the line
 * cap this repository records in `scripts/line-cap.mjs`, which is also why the activity's
 * `model` and `root` are `internal` rather than `private`.
 */
internal object EpubPageSemantics {

    /**
     * The two turns, on every web view under [root].
     *
     * On the web view rather than on a parent, because a screen reader offers the actions of
     * the element it is focused on and the reader is focused on the text. The walk mirrors
     * [PublicationEgress], and for the same reason: the app is handed a fragment's view and
     * the page is drawn by a [WebView] whatever the toolkit version.
     *
     * `ViewCompat` replaces an action that carries the same label, so the repeated call this
     * gets — one per page fragment, and again on a restore — adds no duplicate.
     */
    fun install(root: View, turn: (Boolean) -> Unit) {
        val next = root.context.getString(R.string.reader_turn_next_page)
        val previous = root.context.getString(R.string.reader_turn_previous_page)
        forEachWebView(root) { page ->
            ViewCompat.addAccessibilityAction(page, next) { _, _ -> turn(true); true }
            ViewCompat.addAccessibilityAction(page, previous) { _, _ -> turn(false); true }
        }
    }

    /**
     * Says where a turn arrived, on the view that outlives the turn.
     *
     * A polite live region over a state description rather than `announceForAccessibility`,
     * which the platform deprecated: a live region is read whatever holds accessibility
     * focus, and the reader's focus is somewhere inside the page's web view. `root` is the
     * frame the whole reader is drawn in, so it survives the page fragment the turn replaced.
     * The comic reader states its position the same way (`PageTurnSemantics.kt`).
     */
    fun announce(root: View, position: String) {
        root.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        root.stateDescription = position
    }

    private fun forEachWebView(view: View, apply: (WebView) -> Unit) {
        when (view) {
            is WebView -> apply(view)
            is ViewGroup ->
                for (index in 0 until view.childCount) {
                    forEachWebView(view.getChildAt(index), apply)
                }
        }
    }
}

/**
 * Follows the navigator, and says out loud where each turn arrived.
 *
 * The announcement hangs off the position rather than off the turn. A reflowable page moves
 * from a tap zone, an arrow key, a game controller, a volume button, a swipe, Fast fade and
 * the accessibility action, and a reader who missed one of those paths would get a silence
 * indistinguishable from the rest working. `EpubReaderViewModel.follow` sets the chapter and
 * the remainder before the progression, so the progression is the last thing to change and
 * everything the sentence needs is current when it does.
 *
 * The first value is dropped: a `StateFlow` replays, and the 0.0 it was built with is not a
 * position anybody turned to.
 *
 * The sentence is the menu's own, from [readingPositionSentence] — `ebook-reader` states a
 * reflowable position "in words, in one line", and a position said two ways is two positions.
 */
internal fun EpubReaderActivity.followAndAnnounce(locators: StateFlow<Locator>) {
    model.follow(locators)
    lifecycleScope.launch {
        model.progression.drop(1).collect {
            EpubPageSemantics.announce(root, readingPositionSentence(readingPosition()))
        }
    }
}

/** Where the reader is, as the menu's own three facts. */
internal fun EpubReaderActivity.readingPosition(): ReadingPositionLine = ReadingPositionLine.of(
    totalProgression = model.progression.value,
    chapter = model.chapterTitle.value,
    withinChapter = model.withinChapter.value,
)
