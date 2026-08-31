package app.storyarc.feature.epubreader

import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.graphics.Color as AndroidColor
import android.widget.FrameLayout
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.res.stringResource
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentManager
import kotlinx.coroutines.flow.MutableStateFlow
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.HyperlinkNavigator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import androidx.fragment.app.FragmentContainerView
import androidx.fragment.app.commitNow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.compose.ui.graphics.toArgb
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.HighlightColour
import app.storyarc.core.model.AnnotationExport
import app.storyarc.core.model.ExternalLink
import app.storyarc.core.model.Bookmark
import app.storyarc.core.model.SearchMatch
import app.storyarc.core.model.PageTransition
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.theme.swatch
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.chosenLanguage
import app.storyarc.core.persistence.speaking
import app.storyarc.core.designsystem.theme.resolved
import app.storyarc.core.persistence.AnnotationStore
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
class EpubReaderActivity : FragmentActivity(), EpubNavigatorFragment.Listener {

    /**
     * What to do with a link inside the book.
     *
     * `ebook-reader`: "a footnote opens in place as a popover, and a longer jump navigates
     * with a control to return to where they were". Readium tells the two apart -- it
     * fetches a note's own markup and hands it over as a [HyperlinkNavigator.FootnoteContext]
     * -- so this only has to decide what each one means here.
     *
     * A note is refused: answering no keeps the reader on their page and their place in the
     * sentence, which is what "in place" means. Anything else is a real jump, so where they
     * were is written down first and offered back.
     */
    @OptIn(ExperimentalReadiumApi::class)
    override fun shouldFollowInternalLink(
        link: Link,
        context: HyperlinkNavigator.LinkContext?,
    ): Boolean {
        val footnote = context as? HyperlinkNavigator.FootnoteContext
        if (footnote != null) {
            model.showNote(footnote.noteContent)
            return false
        }
        model.markReturnPoint()
        return true
    }

    /**
     * A link out of the book.
     *
     * Handed to the system rather than opened in the reader: a book is not a browser, and a
     * page loaded over the text would be the reader losing their place to something the
     * publication does not own. `privacy` is why nothing is prefetched -- this happens on a
     * tap and only on a tap.
     *
     * iOS's `EpubReaderOpening.navigator(_:presentExternalURL:)` makes the same two
     * decisions: which schemes survive, and that the host is named before the reader leaves.
     */
    @OptIn(ExperimentalReadiumApi::class)
    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        // Asked rather than obeyed. The string is the publication's, and `ACTION_VIEW` on it
        // launches whichever installed app registered that scheme with the parameters the
        // book chose. `ExternalLink` keeps `http` and `https` and drops the rest; the dialog
        // then names the host, so the destination is visible before the tap takes effect.
        leaving.value = ExternalLink.of(url.toString())
    }

    /** Where the book is asking to send the reader, or null when it is not asking. */
    private val leaving = MutableStateFlow<ExternalLink?>(null)

    /**
     * The reader said yes. Browsable, so the address goes to a browser rather than to
     * whatever else claimed `http` -- and still inside `runCatching`, because a device with
     * nothing able to open it doing nothing is better than a crash on a link the reader was
     * merely curious about.
     */
    private fun leaveTheBook(going: ExternalLink) {
        leaving.value = null
        runCatching {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(going.url))
                    .addCategory(Intent.CATEGORY_BROWSABLE),
            )
        }
    }

    companion object {
        private const val EXTRA_LOCATION = "location"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SERIES = "series"
        private const val NAVIGATOR_TAG = "epub-navigator"

        /** The decoration group the sentence being spoken is drawn under. */
        private const val SPOKEN_GROUP = "spoken"

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
            annotationStore = AnnotationStore.open(applicationContext),
            series = intent.getStringExtra(EXTRA_SERIES),
            linkedPreset = appearance.linkedPreset,
        )
    }

    /**
     * Settings › Appearance, read once when the book opens.
     *
     * One read of one store, resolved here because "System" is a question about the device
     * and only something holding a `Context` can answer it. [ReaderAppearance] says which
     * of its answers wants the reader's literal choice and which wants the resolved one,
     * and why the two differ.
     *
     * **Once is enough, because nothing can change the answer while this activity lives.**
     * An earlier version of this note said the opposite -- that a reader could leave an open
     * book by the home button, change appearance in the other activity and come back to this
     * one still alive -- and the manifests do not bear that out. This activity declares no
     * `launchMode`, `taskAffinity` or `documentLaunchMode`, and the `intent` above adds no
     * flags, so it stacks on `MainActivity` in the one task: home backgrounds that task, and
     * the launcher icon and recents resume its top activity, which is the book. Every route
     * back to `MainActivity` ends this one first -- back and the close button `finish()`, and
     * the launcher quick actions carry `CLEAR_TOP or SINGLE_TOP`, which clears everything
     * above it. Nothing in this module writes appearance either, and the annotation share
     * sheet sends `text/plain`, which the app's own `SEND` filter does not match.
     *
     * A cross-app handover carrying `FLAG_ACTIVITY_NEW_TASK` -- a file manager passing
     * StoryArc a book while a book is open -- is the one candidate left, and what the
     * framework does with it for a `standard` activity wants a device rather than a guess.
     * Re-reading in `onResume` would not be free if it were reachable. `PaperGrainOverlay` is
     * composed inside this activity's `StoryArcTheme` and lands on the page, and it draws on
     * `LocalIsNaturalTheme`, which the theme computes from this value -- so a live appearance
     * adds or withdraws Natural's grain over the reading page mid-book. And a reader who
     * linked the reading theme to appearance would get a chrome that moved while
     * [ReaderAppearance.linkedPreset] stayed: the true-black-chrome-over-a-paper-page pairing
     * `settings-and-about` calls legitimate for the readers who did *not* link the two.
     *
     * `SYSTEM` is exempt from all of it, because it is the one value the theme keeps asking
     * about: `StoryArcTheme` reads the device's own night mode from inside the composition,
     * so a device that flips theme mid-chapter still takes the reader's chrome with it.
     */
    private val appearance: ReaderAppearance by lazy {
        val settings = SettingsStore.open(applicationContext).settings()
        ReaderAppearance.of(settings, settings.appearance.resolved(resources.configuration))
    }

    private lateinit var container: FragmentContainerView

    /// The navigator's parent, which steals a horizontal drag only while Fast fade is on.
    private lateinit var interceptor: TurnInterceptor

    /// What the dip is added to, above the book and below the chrome.
    private lateinit var root: FrameLayout

    /** A turn already running. A second swipe during one would fade over a fade. */
    private var isTurning = false

    /**
     * The publication, once it is open and Readium can extract text from it.
     *
     * Held so pressing play has something to hand [ReadAloudHost] — the session is built
     * when a listener asks for it, not when the book opens, because it outlives this screen
     * and a screen should not create something longer-lived than itself for nobody.
     */
    private var speakable: Publication? = null

    /**
     * Whether the control belongs on screen at all.
     *
     * Its own flow: the chrome is composed before the publication is parsed, so the answer
     * has to arrive rather than be asked for.
     */
    private val canReadAloud = MutableStateFlow(false)

    /**
     * The shade's copy of the transport, which from API 33 has to be asked for.
     *
     * Nothing is done with the answer. Refusing does not stop the voice and does not take
     * the lock screen's own media controls away -- those come from the media session -- so
     * the only honest response to a refusal is to carry on without the notification.
     */
    private val notifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /**
     * `localization`: the reader's own language, before anything reads a resource.
     *
     * The same three lines `MainActivity` has, and for the same reason: a `Popup` is its own
     * window built from this context, so an overridden `Configuration` carried down the
     * composition would reach the page and none of the menus over it. Without this the whole
     * of the reader -- 109 string keys across 94 `stringResource` call sites -- stayed in the
     * system language the moment a book opened, while every screen behind it was in the
     * reader's.
     *
     * Nothing recreates this activity on a language change, and that matters less than it
     * reads: the note on [appearance] establishes that a reader cannot reach Settings with
     * this activity alive, so there is no trip to come back from. What stays true is the
     * asymmetry -- a colour is a value the composition reads, while a language is applied
     * here once against the context the activity was built on, so replacing one does need
     * the activity rebuilt.
     */
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase.speaking(newBase.chosenLanguage()))
    }

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        // The navigator cannot be restored: its publication is not parcelable, and
        // re-parsing takes a moment. Readium provides a dummy factory for exactly
        // this window — it lets the restore complete so the real fragment can
        // replace it once the book is open again.
        if (savedInstanceState != null) {
            supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        }
        // Before anything is committed, so no page fragment can be created without it.
        // ADR-0015: a publication may not reach the network, and the earliest the app can
        // reach a page's web view is the callback that follows the fragment's own
        // `onCreateView`. Recursive, because the pages live in the navigator's child
        // fragment manager rather than this one.
        supportFragmentManager.registerFragmentLifecycleCallbacks(
            object : FragmentManager.FragmentLifecycleCallbacks() {
                override fun onFragmentViewCreated(
                    fragmentManager: FragmentManager,
                    fragment: Fragment,
                    view: View,
                    savedInstanceState: Bundle?,
                ) = PublicationEgress.deny(view)
            },
            true,
        )
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
                // Read, not fixed. `settings-and-about`'s appearance is the reader's and it
                // applies "across the whole app"; the Material You opt-out is
                // `native-experience`'s and belongs to the same choice. Both come from the
                // one read on `appearance`, which also carries why this one is the literal
                // choice rather than the resolved one.
                StoryArcTheme(
                    appearance = appearance.chrome,
                    useDynamicColor = appearance.useDynamicColor,
                ) {
                    val progression by model.progression.collectAsStateWithLifecycle()
                    val chapter by model.chapterTitle.collectAsStateWithLifecycle()
                    val withinChapter by model.withinChapter.collectAsStateWithLifecycle()
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
                    val note by model.note.collectAsStateWithLifecycle()
                    val returnPoint by model.returnPoint.collectAsStateWithLifecycle()
                    val canSpeak by canReadAloud.collectAsStateWithLifecycle()
                    // The session belongs to `ReadAloudHost`, and this screen only observes
                    // it. Scoped to this book, because a listener looking at one book while
                    // another is being spoken must not get a transport in this chrome that
                    // would pause a book they cannot see.
                    val spoken by ReadAloudHost.session.collectAsStateWithLifecycle()
                    val spokenBook by ReadAloudHost.book.collectAsStateWithLifecycle()
                    val isThisBook = spokenBook?.id == bookId
                    val annotations by model.annotations.collectAsStateWithLifecycle()
                    val writing by writingNote.collectAsStateWithLifecycle()
                    var editingNote by remember { mutableStateOf<Annotation?>(null) }
                    // Either route into the editor: the selection bar's "Note", which
                    // highlights first and lands here, or a row's own pencil. Named apart
                    // from `note` above, which is the footnote a reader tapped.
                    val writtenOn = writing ?: editingNote
                    var isShowingTheme by remember { mutableStateOf(false) }
                    var isShowingContents by remember { mutableStateOf(false) }

                    // The other half of the two-control chrome: one button leaves the book
                    // and this one is everything else. See `EpubMenuSheet.kt`.
                    var isShowingMenu by remember { mutableStateOf(false) }
                    var contentsTab by remember { mutableStateOf(ContentsTab.CONTENTS) }

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

                    // `ebook-reader`: a footnote "opens in place". A bottom sheet is the
                    // platform's own in-place, and it leaves the page it was tapped on
                    // visible behind it.
                    note?.let { text ->
                        ModalBottomSheet(onDismissRequest = { model.dismissNote() }) {
                            Text(
                                text = text,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(
                                    horizontal = StoryArcSpace.gutter,
                                    vertical = StoryArcSpace.lg,
                                ),
                            )
                        }
                    }

                    // A link out of the book names where it goes before it goes there.
                    val going by leaving.collectAsStateWithLifecycle()
                    going?.let { destination ->
                        LeaveTheBookDialog(
                            leaving = destination,
                            onOpen = { leaveTheBook(destination) },
                            onDismiss = { leaving.value = null },
                        )
                    }

                    writtenOn?.let { mark ->
                        NoteDialog(
                            initial = mark.note,
                            onSave = { text ->
                                model.annotate(mark, text)
                                writingNote.value = null
                                editingNote = null
                            },
                            onDismiss = {
                                writingNote.value = null
                                editingNote = null
                            },
                        )
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
                            annotations = annotations,
                            onGoToAnnotation = { mark ->
                                go(mark)
                                isShowingContents = false
                            },
                            onEditAnnotation = { editingNote = it },
                            onRemoveAnnotation = { model.removeAnnotation(it.id) },
                            onExportAnnotations = { format -> share(annotations, format) },
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
                            opensOn = contentsTab,
                        )
                    }

                    if (isShowingTheme) {
                        // Words from where the reader is, read once when the sheet opens.
                        // The position does not move while the sheet is up, and re-reading
                        // the resource on every slider step would put a disk read inside a
                        // drag.
                        var excerpt by remember { mutableStateOf("") }
                        LaunchedEffect(Unit) { excerpt = model.previewExcerpt() }

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
                            chapter = chapter,
                            excerpt = excerpt,
                        )
                    }

                    if (isShowingMenu) {
                        EpubMenuSheet(
                            facts = EpubMenuFacts(
                                chapter = chapter,
                                progression = progression,
                                withinChapter = withinChapter,
                                isPageBookmarked = isPageBookmarked,
                                isContentsReady = contents != null,
                                canReadAloud = canSpeak,
                                isReadingAloud = isThisBook && spoken.isActive,
                            ),
                            actions = EpubMenuActions(
                                onDismiss = { isShowingMenu = false },
                                onOpenContents = { panel ->
                                    contentsTab = panel
                                    isShowingMenu = false
                                    isShowingContents = true
                                },
                                onToggleBookmark = { model.toggleBookmark() },
                                onOpenTheme = {
                                    isShowingMenu = false
                                    isShowingTheme = true
                                },
                                onStartReadAloud = {
                                    isShowingMenu = false
                                    startReadAloud()
                                },
                                onStopReadAloud = ReadAloudHost::end,
                            ),
                        )
                    }

                    EpubChrome(
                        failure = failure,
                        isVisible = isVisible,
                        onClose = { finish() },
                        onOpenMenu = { isShowingMenu = true },
                    )

                    // Not the chrome, and on screen on their own terms — see
                    // `EpubReaderOverlays.kt`.
                    EpubReaderOverlays(
                        canReturn = returnPoint != null,
                        onReturn = { model.takeReturnPoint()?.let { goToLocator(it, remember = false) } },
                        isReadingAloud = isThisBook && spoken.isActive,
                        isSpeaking = isThisBook && spoken.isSpeaking,
                        onToggleReadAloud = ReadAloudHost::toggle,
                        onSkipSentence = ReadAloudHost::skip,
                        onStopReadAloud = ReadAloudHost::end,
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
            configuration = EpubNavigatorFragment.Configuration {
                declareBundledFonts()
                // `ebook-reader`'s selection actions, in the bar Android puts them in.
                selectionActionModeCallback = SelectionActions(
                    onHighlight = { colour -> markSelection(colour) },
                    onNote = { markSelection(HighlightColour.YELLOW, thenWrite = true) },
                    onSearch = { searchSelection() },
                )
            },
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

        prepareReadAloud(publication)
        model.follow(navigator.currentLocator)
        // Painted once the navigator exists: a decoration applied before it is on
        // screen is a decoration Readium has nowhere to put.
        lifecycleScope.launch { drawAnnotations() }
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

    /** A mark the reader is writing on, or null. Held here because the bar cannot hold it. */
    private val writingNote = MutableStateFlow<Annotation?>(null)

    /**
     * Marks what is selected, and paints it.
     *
     * The selection is asked for rather than passed in: Readium reports it through a
     * suspending call on the navigator, and the action bar's callback cannot wait.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun markSelection(colour: HighlightColour, thenWrite: Boolean = false) {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        lifecycleScope.launch {
            val selection = navigator.currentSelection() ?: return@launch
            val mark = model.highlight(selection.locator, colour) ?: return@launch
            navigator.clearSelection()
            drawAnnotations()
            if (thenWrite) writingNote.value = mark
        }
    }

    /** Searches for what is selected, which `ebook-reader` offers beside the colours. */
    @OptIn(ExperimentalReadiumApi::class)
    private fun searchSelection() {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        lifecycleScope.launch {
            val words = navigator.currentSelection()?.locator?.text?.highlight ?: return@launch
            navigator.clearSelection()
            model.search(words)
        }
    }

    /**
     * Paints every mark this publication holds back onto the page.
     *
     * Declared wholesale rather than one at a time: Readium diffs the group against what it
     * is already showing and decides what to redraw, which is cheaper than guessing here.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private suspend fun drawAnnotations() {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        navigator.applyDecorations(
            model.annotations.value.mapNotNull { mark ->
                val locator = runCatching { Locator.fromJSON(JSONObject(mark.locator)) }
                    .getOrNull() ?: return@mapNotNull null
                Decoration(
                    id = mark.id,
                    locator = locator,
                    style = Decoration.Style.Highlight(
                        tint = mark.colour.swatch.toArgb(),
                        isActive = false,
                    ),
                )
            },
            // Its own group so a future one — a search hit, a spoken sentence — can be
            // applied and withdrawn without touching what the reader made.
            "annotations",
        )
    }

    /** Goes to a mark. The same journey a bookmark takes, from the same kind of record. */
    @OptIn(ExperimentalReadiumApi::class)
    private fun go(annotation: Annotation) = goToLocator(annotation.locator)

    /**
     * Hands the marks to whatever the reader wants to put them in.
     *
     * The platform's own share sheet rather than a file this app writes: `ebook-reader` asks
     * for them to be "exportable", and where they go is the reader's business.
     */
    private fun share(annotations: List<Annotation>, format: AnnotationExport.Format) {
        val document = AnnotationExport.document(
            annotations,
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
            format = format,
        )
        if (document.isBlank()) return
        startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, document)
                },
                null,
            ),
        )
    }

    /** Goes to a search hit. The same journey a bookmark takes, from the same kind of record. */
    @OptIn(ExperimentalReadiumApi::class)
    private fun go(match: SearchMatch) = goToLocator(match.locator)

    /**
     * Builds the voice once the publication is open.
     *
     * Here rather than on the first press, because whether this book can be read aloud at
     * all decides whether the control appears -- and that is [SpokenSentences]'s answer,
     * which needs the parsed publication.
     */
    private fun prepareReadAloud(publication: Publication) {
        val handover = SessionHandover.opening(bookId, ReadAloudHost.book.value?.id)

        // One book at a time. `ebook-reader`: opening a different publication "ends the
        // session at a sentence boundary and the position it reached is recorded before the
        // new publication opens" — and the sentence locator the voice is on *is* a sentence
        // boundary, which is what makes ending here honest rather than abrupt.
        if (handover == SessionHandover.DISPLACE) ReadAloudHost.end()

        canReadAloud.value = SpokenSentences.isSpeakable(publication)
        if (!canReadAloud.value) return
        speakable = publication

        if (handover != SessionHandover.ADOPT) return
        // The book on screen is the book being spoken. No restart: this screen takes over
        // drawing the sentence the voice is already on, and the voice never notices.
        ReadAloudHost.adopt(drawing)
        lifecycleScope.launch { ReadAloudHost.redrawSpokenSentence() }
    }

    /**
     * This screen, as the session sees it.
     *
     * An object of its own rather than the activity implementing [SpokenSentenceFollower]:
     * `Sentence` is internal to this module and this activity is public, so an override of
     * it here would export a type nothing outside the module is allowed to name.
     */
    private val drawing = object : SpokenSentenceFollower {
        override suspend fun drawSpokenSentence(sentence: Sentence) =
            followSpokenSentence(sentence)

        override suspend fun withdrawSpokenHighlight() = clearSpokenHighlight()
    }

    /** What this screen's publication is called wherever a publication is named. */
    private val bookId: String
        get() = PublicationIdentity(
            normalizedPath = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
        ).stableId

    /**
     * Starts speaking from where the reader is.
     *
     * `ebook-reader`: speech "begins at the current position". The navigator's own locator
     * is that position -- not the top of the resource, which would make a reader listen
     * back to what they have already read.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun startReadAloud() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notifications.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        val publication = speakable ?: return
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
        // Everything the session will need once this screen is gone goes across in this one
        // call — including where to write the position, because after it the activity is
        // free to be destroyed and the voice is not.
        ReadAloudHost.begin(
            // The application context, not this activity: the session outlives both a
            // configuration change and this screen, and hands the same context to a
            // foreground service.
            context = applicationContext,
            book = SpokenBook(
                id = bookId,
                location = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
                title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
                series = intent.getStringExtra(EXTRA_SERIES),
                author = publication.metadata.authors.firstOrNull()?.name,
            ),
            publication = publication,
            position = model.spokenPosition(),
            from = navigator?.currentLocator?.value,
            drawnBy = drawing,
        )
    }

    /**
     * Draws the sentence being spoken and brings the page to it.
     *
     * Its own decoration group, beside `annotations`: the highlight follows the voice and
     * is withdrawn when the voice stops, and neither of those should disturb a mark the
     * reader made.
     *
     * Moving the page is also what keeps the position record honest. `reading-progress`
     * writes on every navigator move, so a book listened to for an hour resumes where the
     * listening got to rather than where the reading stopped.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private suspend fun followSpokenSentence(sentence: Sentence) {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        navigator.applyDecorations(
            listOf(
                Decoration(
                    id = SPOKEN_GROUP,
                    locator = sentence.locator,
                    style = Decoration.Style.Highlight(
                        tint = SpokenHighlight.TINT,
                        isActive = false,
                    ),
                ),
            ),
            SPOKEN_GROUP,
        )
        navigator.go(sentence.locator, animated = false)
    }

    @OptIn(ExperimentalReadiumApi::class)
    private suspend fun clearSpokenHighlight() {
        val navigator =
            supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
                ?: return
        navigator.applyDecorations(emptyList(), SPOKEN_GROUP)
    }

    override fun onDestroy() {
        // The voice outlives this screen. `ebook-reader`: closing the publication while it
        // is being read leaves speech running and returns the listener "to whatever they
        // were doing in the app rather than being kept in the book" -- so this lets go of
        // the session rather than ending it. Releasing the controller here is what made
        // finishing the reader the same act as stopping the voice, which is a different
        // case from backgrounding and the one the foreground service never answered.
        ReadAloudHost.release(drawing)
        speakable = null
        super.onDestroy()
    }

    /**
     * Goes somewhere in the book, remembering where the reader was.
     *
     * `ebook-reader` asks for the return control on "a longer jump" from a link. It is
     * offered on every long jump instead -- a contents entry, a search hit, a bookmark --
     * because they are the same act from the reader's side, and a control that appeared
     * after one kind of jump and not another would look like a bug rather than a rule.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun goToLocator(json: String, remember: Boolean = true) {
        // Not on the way back: the control's whole promise is that it goes away once it
        // has done what it offers, and a return that recorded where it returned *from*
        // would leave a button that bounces the reader between two pages for ever.
        if (remember) model.markReturnPoint()
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

        model.markReturnPoint()
        navigator.go(link, animated = false)
    }
}
