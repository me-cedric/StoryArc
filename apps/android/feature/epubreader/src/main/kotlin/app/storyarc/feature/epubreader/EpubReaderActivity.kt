package app.storyarc.feature.epubreader

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowManager
import android.graphics.Color as AndroidColor
import android.widget.FrameLayout
import androidx.activity.compose.setContent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.res.stringResource
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import androidx.fragment.app.commitNow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.Bookmark
import app.storyarc.core.model.SearchMatch
import app.storyarc.core.model.PageTransition
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.model.presetMatching
import app.storyarc.core.designsystem.theme.resolved
import app.storyarc.core.persistence.BookmarkStore
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ReaderPreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.ExperimentalReadiumApi
import org.json.JSONObject
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url

/**
 * A reflowable book, open.
 *
 * Its own activity rather than a Compose screen. Readium's EPUB navigator is a
 * `Fragment` and needs a `FragmentManager` with a factory installed before the
 * fragment is created; hosting that inside Compose means fighting two lifecycles
 * at once for no gain. An activity is the platform's own answer to "a screen with
 * a fragment", and the chrome on top of it is still Compose.
 *
 * `ebook-reader` forbids presenting a reflowable page number as a stable identity —
 * the count changes with the type size — so the chrome shows a percentage and the
 * chapter, which do not.
 *
 * Typography controls are absent rather than disabled. They belong to the
 * `reader-theming-and-page-transitions` change, and a sheet of sliders that does
 * nothing would be worse than no sheet at all.
 */
class EpubReaderActivity : FragmentActivity() {

    companion object {
        private const val EXTRA_LOCATION = "location"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SERIES = "series"
        private const val NAVIGATOR_TAG = "epub-navigator"

        /**
         * Between the book and the chrome.
         *
         * Over the book because that is what it is dipping, and under the chrome because
         * a progress bar that vanished for a quarter of a second on every turn would be
         * the transition drawing attention to itself.
         */
        private const val DIP_INDEX = 1

        /** Long enough for Readium to re-paginate, short enough not to be seen. */
        private const val REFLOW_SETTLE_MILLIS = 120L

        /**
         * @param location where the book lives, as the library recorded it: a
         *   filesystem path, or a `content://` URI from a folder the user picked.
         */
        /**
         * @param series what shelf the book sits on, so the theme it is read with is
         *   the one the rest of the series was read with. Null for a standalone book,
         *   which then remembers a theme of its own.
         */
        fun intent(
            context: Context,
            location: String,
            title: String,
            series: String?,
        ): Intent =
            Intent(context, EpubReaderActivity::class.java)
                .putExtra(EXTRA_LOCATION, location)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_SERIES, series)
    }

    private val model: EpubReaderViewModel by lazy {
        EpubReaderViewModel(
            application = application,
            location = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
            identity = PublicationIdentity(
                normalizedPath = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
            ),
            progress = ProgressStore.open(applicationContext),
            themeStore = ReaderPreferences.open(applicationContext),
            bookmarkStore = BookmarkStore.open(applicationContext),
            series = intent.getStringExtra(EXTRA_SERIES),
            // Resolved here, because "System" is a question about the device and only
            // something holding a `Context` can answer it. Null when the reader has not
            // opted in, which leaves the shelf's own theme in force.
            linkedPreset = SettingsStore.open(applicationContext).settings()
                .takeIf { it.linkReadingThemeToAppearance }
                ?.let { presetMatching(it.appearance.resolved(resources.configuration)) },
        )
    }

    private lateinit var container: FragmentContainerView

    /// The navigator's parent, which steals a horizontal drag only while Fast fade is on.
    private lateinit var interceptor: TurnInterceptor

    /// What the dip is added to, above the book and below the chrome.
    private lateinit var root: FrameLayout

    /** A turn already running. A second swipe during one would fade over a fade. */
    private var isTurning = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // The navigator cannot be restored: its publication is not parcelable, and
        // re-parsing takes a moment. Readium provides a dummy factory for exactly
        // this window — it lets the restore complete so the real fragment can
        // replace it once the book is open again.
        if (savedInstanceState != null) {
            supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        }
        super.onCreate(savedInstanceState)

        // `comic-reader`'s rule, and it reads the same for a book: a long look at
        // one page is reading, not idling. The flag is scoped to this window, so
        // leaving restores the device's own behaviour.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        container = FragmentContainerView(this).apply {
            id = ViewGroup.generateViewId()
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }

        val chrome = ComposeView(this).apply {
            setContent {
                StoryArcTheme(appearance = AppearanceMode.SYSTEM, useDynamicColor = true) {
                    val progression by model.progression.collectAsStateWithLifecycle()
                    val chapter by model.chapterTitle.collectAsStateWithLifecycle()
                    val failure by model.failure.collectAsStateWithLifecycle()
                    val isVisible by model.isChromeVisible.collectAsStateWithLifecycle()
                    val theme by model.theme.collectAsStateWithLifecycle()
                    val values by model.values.collectAsStateWithLifecycle()
                    val transition by model.transition.collectAsStateWithLifecycle()
                    val brightness by model.brightness.collectAsStateWithLifecycle()
                    val contents by model.tableOfContents.collectAsStateWithLifecycle()
                    val resource by model.currentResource.collectAsStateWithLifecycle()
                    val bookmarks by model.bookmarks.collectAsStateWithLifecycle()
                    val isPageBookmarked by model.isPageBookmarked.collectAsStateWithLifecycle()
                    val matches by model.matches.collectAsStateWithLifecycle()
                    val isSearching by model.isSearching.collectAsStateWithLifecycle()
                    var isShowingTheme by remember { mutableStateOf(false) }
                    var isShowingContents by remember { mutableStateOf(false) }

                    // `reading-themes`: reader-local. A window attribute rather than
                    // the system setting, so it reverts when this screen goes away.
                    LaunchedEffect(brightness) {
                        window.attributes = window.attributes.apply {
                            screenBrightness = brightness
                                ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        }
                    }

                    // `reading-themes`: the change is "visible immediately in the
                    // reader behind the sheet", so the navigator is told the moment
                    // either half of the theme changes rather than when the sheet
                    // closes.
                    LaunchedEffect(theme, values, transition) { applyTheme() }

                    // `page-transitions`: the reader picks a page turn *after* the book
                    // is open, so ownership changes here rather than when the navigator
                    // is created. Nil hands Readium back its own Slide.
                    LaunchedEffect(transition) {
                        interceptor.onTurn =
                            if (transition == PageTransition.FAST_FADE) ::turnWithFade else null
                    }

                    if (isShowingContents) {
                        ContentsBottomSheet(
                            entries = contents.orEmpty(),
                            currentResource = resource,
                            bookmarks = bookmarks,
                            matches = matches,
                            isSearching = isSearching,
                            onSearch = { model.search(it) },
                            onGoToMatch = { match ->
                                go(match)
                                isShowingContents = false
                            },
                            onGo = { link ->
                                go(link)
                                isShowingContents = false
                            },
                            onGoToBookmark = { bookmark ->
                                go(bookmark)
                                isShowingContents = false
                            },
                            onRemoveBookmark = { model.removeBookmark(it.id) },
                            onDismiss = { isShowingContents = false },
                        )
                    }

                    if (isShowingTheme) {
                        ThemeBottomSheet(
                            theme = theme,
                            values = values,
                            brightness = brightness,
                            onAdopt = model::adopt,
                            onChange = model::change,
                            onSet = model::set,
                            onBrightness = model::setBrightness,
                            onRestore = model::restoreTheme,
                            onLeavePublisherStyles = model::leavePublisherStyles,
                            onAdoptColours = model::adoptColours,
                            onDiscardColours = model::discardCustomColours,
                            choices = model.transitions,
                            onChooseTransition = model::choose,
                            onDismiss = { isShowingTheme = false },
                        )
                    }

                    EpubChrome(
                        title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
                        chapter = chapter,
                        progression = progression,
                        failure = failure,
                        isVisible = isVisible,
                        isContentsReady = contents != null,
                        isPageBookmarked = isPageBookmarked,
                        onClose = { finish() },
                        onToggleBookmark = { model.toggleBookmark() },
                        onOpenContents = { isShowingContents = true },
                        onOpenTheme = { isShowingTheme = true },
                    )
                }
            }
        }

        interceptor = TurnInterceptor(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            addView(container)
        }
        root = FrameLayout(this).apply {
            addView(interceptor)
            addView(chrome)
        }
        setContentView(root)

        lifecycleScope.launch { showNavigator() }
    }

    // Readium marks its input listener experimental. Opted into here rather than
    // module-wide, so the day it changes the compiler points at the one call site.
    @OptIn(ExperimentalReadiumApi::class)
    private suspend fun showNavigator() {
        val publication = model.open() ?: return

        val factory = EpubNavigatorFactory(publication)
        supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
            initialLocator = model.initialLocator(),
            // Without these a preference naming a bundled family resolves to nothing
            // and the page falls back silently.
            configuration = EpubNavigatorFragment.Configuration { declareBundledFonts() },
        )

        // Replace rather than add: on a process restore the dummy fragment is
        // already in the container, and adding beside it would leave a blank view
        // stacked over the book.
        supportFragmentManager.commitNow {
            replace(container.id, EpubNavigatorFragment::class.java, Bundle(), NAVIGATOR_TAG)
        }

        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return

        // Through Readium's own input listener, not a Compose gesture: a gesture
        // layered over the web view swallows the taps the reader needs to turn
        // pages and follow links.
        navigator.addInputListener(
            object : InputListener {
                override fun onTap(event: TapEvent): Boolean {
                    model.toggleChrome()
                    return true
                }
            },
        )

        model.follow(navigator.currentLocator)
        applyTheme()
    }

    /**
     * Pushes the current theme into the navigator.
     *
     * The activity does this rather than the view model, because the navigator is a
     * fragment the activity owns and a view model holding one would outlive it.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun applyTheme() {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return

        // Where the reader is, before the reflow moves it.
        //
        // `ebook-reader`: "the reading position is preserved to the paragraph, not
        // the page number". Submitting preferences re-paginates the resource, and
        // Readium lands on the *progression* rather than the paragraph — measured on
        // an emulator, a size change moved the reader fourteen paragraphs back
        // inside the same chapter. Going to the stored locator afterwards puts them
        // where the text was.
        val locator = navigator.currentLocator.value
        navigator.submitPreferences(model.preferences)

        // ponytail: after the reflow, not during it. `submitPreferences` has no
        // completion, so this waits a frame's worth rather than observing the
        // relayout. If Readium ever exposes a settled signal, wait on that instead.
        lifecycleScope.launch {
            delay(REFLOW_SETTLE_MILLIS)
            navigator.go(locator, animated = false)
        }
    }

    /**
     * Goes back to a mark.
     *
     * The stored locator rather than a position derived from it: a bookmark records where
     * Readium said the reader was, and handing that back is the only way to land on the
     * same words after a type size has moved every page break.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun go(bookmark: Bookmark) = goToLocator(bookmark.locator)

    /** Goes to a search hit. The same journey a bookmark takes, from the same kind of record. */
    @OptIn(ExperimentalReadiumApi::class)
    private fun go(match: SearchMatch) = goToLocator(match.locator)

    @OptIn(ExperimentalReadiumApi::class)
    private fun goToLocator(json: String) {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        val locator = runCatching { Locator.fromJSON(JSONObject(json)) }.getOrNull() ?: return
        navigator.go(locator, animated = false)
    }

    /**
     * Turns a page with a transition StoryArc draws rather than one Readium draws.
     *
     * The dip is opaque before the navigator moves, so the swap is never on screen: what
     * a reader sees is the page they were on fading to the page colour, and the next one
     * arriving out of it. `page-transitions` calls this Fast fade.
     *
     * A turn that cannot happen — the last page, the first page — takes the dip straight
     * back off instead of completing, because a full fade there would read as a turn that
     * did happen.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun turnWithFade(forward: Boolean) {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        if (isTurning) return
        isTurning = true

        lifecycleScope.launch {
            try {
                FadeTurn(root, DIP_INDEX).run(
                    pageColour = AndroidColor.parseColor(model.theme.value.background),
                ) {
                    if (forward) {
                        navigator.goForward(animated = false)
                    } else {
                        navigator.goBackward(animated = false)
                    }
                }
            } finally {
                isTurning = false
            }
        }
    }

    /**
     * Jumps to a table-of-contents entry.
     *
     * The navigator is asked for the link rather than for a locator built here: it is
     * Readium that knows how the entry's fragment maps onto a position in the resource.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun go(link: Link) {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return

        navigator.go(link, animated = false)
    }
}

/** The table of contents, in the same modal bottom sheet the theme sheet uses. */
@OptIn(ExperimentalMaterial3Api::class)
@androidx.compose.runtime.Composable
private fun ContentsBottomSheet(
    entries: List<Link>,
    currentResource: Url?,
    bookmarks: List<Bookmark>,
    matches: List<SearchMatch>,
    isSearching: Boolean,
    onGo: (Link) -> Unit,
    onGoToBookmark: (Bookmark) -> Unit,
    onRemoveBookmark: (Bookmark) -> Unit,
    onSearch: (String) -> Unit,
    onGoToMatch: (SearchMatch) -> Unit,
    onDismiss: () -> Unit,
) {
    // `ebook-reader` puts bookmarks "alongside the table of contents", and searching inside
    // the book is the third way of asking the same question — where in this book do I go.
    // One sheet rather than three, because a reader who opened the wrong one would have to
    // close it to ask again.
    var tab by remember { mutableIntStateOf(0) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        PrimaryTabRow(selectedTabIndex = tab) {
            listOf(R.string.epub_contents, R.string.epub_bookmarks, R.string.epub_search)
                .forEachIndexed { index, label ->
                    Tab(
                        selected = tab == index,
                        onClick = { tab = index },
                        text = { Text(stringResource(label)) },
                    )
                }
        }

        when (tab) {
            1 -> Bookmarks(
                bookmarks = bookmarks,
                onGo = onGoToBookmark,
                onRemove = onRemoveBookmark,
            )
            2 -> SearchInBook(
                matches = matches,
                isSearching = isSearching,
                onSearch = onSearch,
                onGo = onGoToMatch,
            )
            else -> TableOfContents(
                entries = entries,
                currentResource = currentResource,
                onGo = onGo,
            )
        }
    }
}

/**
 * The theme sheet, in the platform's own modal bottom sheet.
 *
 * `native-experience` wants the sheet to look like the platform's; iOS gets a
 * detented sheet on Liquid Glass and Android gets this.
 */
@OptIn(ExperimentalMaterial3Api::class)
@androidx.compose.runtime.Composable
private fun ThemeBottomSheet(
    theme: app.storyarc.core.model.ReadingTheme,
    values: app.storyarc.core.model.ThemeValues,
    brightness: Float?,
    onAdopt: (app.storyarc.core.model.ThemePreset) -> Unit,
    onChange: (app.storyarc.core.model.ThemeAxis, app.storyarc.core.model.ThemeValues) -> Unit,
    onSet: (app.storyarc.core.model.ThemeAxis, Double) -> Unit,
    onBrightness: (Float) -> Unit,
    onRestore: () -> Unit,
    onLeavePublisherStyles: () -> Unit,
    onAdoptColours: (app.storyarc.core.model.ReaderPalette) -> Boolean,
    onDiscardColours: () -> Unit,
    choices: app.storyarc.core.model.TransitionChoices,
    onChooseTransition: (PageTransition) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        ThemeSheet(
            theme = theme,
            values = values,
            brightness = brightness,
            onAdopt = onAdopt,
            onChange = onChange,
            onSet = onSet,
            onBrightness = onBrightness,
            onRestore = onRestore,
            onLeavePublisherStyles = onLeavePublisherStyles,
            onAdoptColours = onAdoptColours,
            onDiscardColours = onDiscardColours,
            choices = choices,
            onChooseTransition = onChooseTransition,
        )
    }
}
