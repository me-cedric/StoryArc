package app.storyarc.feature.epubreader

import android.app.Application
import android.net.Uri
import app.storyarc.core.model.PublicationIdentity
import android.provider.Settings
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.model.TotalProgression
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.setting
import app.storyarc.core.model.values
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ReaderPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/**
 * What the EPUB screen knows.
 *
 * Deliberately not an `AndroidViewModel`: the activity owns it and its lifetime is
 * the activity's. Readium's `Publication` holds open file handles, so a value that
 * outlived the screen would hold them too.
 *
 * iOS's `EpubReaderModel` does the same three things — open, follow, record.
 */
class EpubReaderViewModel(
    private val application: Application,
    private val location: String,
    private val identity: PublicationIdentity,
    private val progress: ProgressStore?,
    /**
     * Where the reader's theme choices live between sessions. Null in a test.
     *
     * Named `themeStore` rather than `preferences`, because this type already has a
     * `preferences` — the Readium value it hands the navigator. Two different things
     * with one name in one file is how a wrong one gets passed.
     */
    private val themeStore: ReaderPreferences? = null,
    /** What shelf this book sits on. Null for a standalone book. */
    series: String? = null,
    /**
     * A preset the *app appearance* dictates, when the reader opted into that.
     *
     * `settings-and-about` keeps appearance and reading theme apart by default and allows
     * "a single opt-in setting" that links them. When it is on, this is what the page is
     * read with, and the shelf's own stored theme is *not* overwritten on open — so turning
     * the setting off again brings it back.
     *
     * One edge, stated rather than glossed: adjusting a theme *while* linked does record it
     * against the shelf, replacing what was there. That is the reader changing their mind
     * on purpose, and a change that silently failed to stick would be the worse surprise.
     *
     * Passed in already resolved, because "System" is a question about the device and the
     * host is the only thing that can answer it.
     */
    linkedPreset: ThemePreset? = null,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * The key this publication remembers its theme under: its series, or itself where
     * it has none. `reading-themes` scopes a theme to the series, and a standalone
     * book is a series of one.
     */
    private val shelf = ShelfMemory.shelf(series, identity.stableId)

    /**
     * Always reflowable. A fixed-layout EPUB never reaches this reader —
     * `ebook-reader` sends it to the comic reader, which has pages.
     */
    private val themeScope = ThemeScope.REFLOWABLE

    private val stored = themeStore?.themes()?.theme(themeScope, shelf) ?: ShelfSettings()

    /**
     * The reading order's hrefs, for the progress fallback below.
     */
    private var readingOrder: List<String> = emptyList()

    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()

    /**
     * How far through the whole publication, 0…1.
     *
     * `ebook-reader`: progress is a percentage, and "the app never presents a
     * reflowable page number as a stable identity".
     */
    private val _progression = MutableStateFlow(0.0)
    val progression: StateFlow<Double> = _progression.asStateFlow()

    private val _chapterTitle = MutableStateFlow<String?>(null)
    val chapterTitle: StateFlow<String?> = _chapterTitle.asStateFlow()

    /**
     * The publication's own navigation, or null until the publication is open.
     *
     * Null and empty are different answers. Empty means the publication declares no
     * navigation, which the sheet says out loud; null means nobody has asked the
     * publication yet, and a sheet opened then would report a bare book that is not bare.
     */
    private val _tableOfContents = MutableStateFlow<List<Link>?>(null)
    val tableOfContents: StateFlow<List<Link>?> = _tableOfContents.asStateFlow()

    /** The resource being read, so the table of contents can mark the reader's place. */
    private val _currentResource = MutableStateFlow<Url?>(null)
    val currentResource: StateFlow<Url?> = _currentResource.asStateFlow()

    /** Which preset is on and which axes have been moved from it. */
    private val _theme = MutableStateFlow(
        // A linked preset wins over the shelf's own theme, and does *not* replace it: the
        // stored theme stays exactly where it is, so turning the setting back off restores
        // it rather than having lost it.
        linkedPreset?.let { ReadingTheme(it) } ?: stored.theme,
    )
    val theme: StateFlow<ReadingTheme> = _theme.asStateFlow()

    /** The typography in force: the preset's own values until an axis is moved. */
    private val _values = MutableStateFlow(linkedPreset?.values ?: stored.values)
    val values: StateFlow<ThemeValues> = _values.asStateFlow()

    /** How a page becomes the next page. Paginated or scrolling, for an EPUB. */
    private val _transition = MutableStateFlow(stored.transition)
    val transition: StateFlow<PageTransition> = _transition.asStateFlow()

    /**
     * What Readium should render with, recomputed whenever either changes.
     *
     * Exposed rather than pushed: the activity owns the navigator and submits this
     * to it, which keeps the view model free of a Readium fragment.
     */
    val preferences get() = _theme.value.preferences(_values.value, _transition.value)

    /**
     * Adopts a preset, discarding any deviation from the last one.
     *
     * `reading-themes`: tapping a preset applies "every axis the preset defines at
     * once and the change is visible immediately in the reader behind the sheet".
     */
    fun adopt(preset: ThemePreset) {
        _theme.value = _theme.value.adopting(preset)
        _values.value = preset.values
    }

    /**
     * Reader-local screen brightness, 0…1, or `null` for the device's own.
     *
     * `reading-themes`: "reader-local screen brightness, independent of the system
     * slider", and the system brightness "is not permanently modified". On Android
     * this is a window attribute, so leaving the activity reverts it without anyone
     * having to remember to.
     */
    private val _brightness = MutableStateFlow<Float?>(null)
    val brightness: StateFlow<Float?> = _brightness.asStateFlow()

    fun setBrightness(value: Float) {
        _brightness.value = value
    }

    /** Sets one slider axis, in one call, so the sheet can drive five of them. */
    fun set(axis: ThemeAxis, value: Double) {
        change(axis, _values.value.setting(axis, value))
    }

    /**
     * Moves one axis, which marks the preset modified without deselecting it.
     *
     * The axis is passed alongside the new values so the model records *which* axis
     * moved — the sheet needs that to offer "restore this preset", and Readium
     * cannot tell us.
     */
    fun change(axis: ThemeAxis, values: ThemeValues) {
        if (!_theme.value.isEffective(axis)) return
        _values.value = values
        _theme.value = _theme.value.deviating(axis)
    }

    /** Puts every axis back to the preset's own values. */
    fun restoreTheme() {
        _theme.value = _theme.value.restored()
        _values.value = _theme.value.preset.values
    }

    /**
     * Which page-turn rows to offer, and which of them this content cannot run.
     *
     * The curl is not refused for lack of a device here but for lack of a *raster*: a
     * reflowable page is live web content. The two reasons are different and the reader
     * is told which.
     */
    val transitions: TransitionChoices
        get() = TransitionChoices(
            chosen = _transition.value,
            // Reflowing text scrolls the way it is read; the axis is not a choice here.
            axis = ScrollAxis.VERTICAL,
            reduceMotion = reduceMotion,
            canCurl = true,
            isReflowable = true,
        )

    /** Chooses a page turn, for this shelf, from now on. */
    fun choose(transition: PageTransition) {
        _transition.value = transition
    }

    /**
     * Whether the reader has asked the system to remove animations.
     *
     * Android has no `UIAccessibility.isReduceMotionEnabled`; what it has is an animator
     * duration scale a reader can set to zero. Read on demand rather than cached,
     * because `page-transitions` requires turning it off mid-session to restore the
     * chosen mode "without the reader being reopened".
     */
    private val reduceMotion: Boolean
        get() = Settings.Global.getFloat(
            application.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f

    /**
     * Puts the reader's own colours in force, or refuses and says why.
     *
     * `reading-themes`: a pairing below 4.5 to 1 "is refused with the measured ratio
     * stated". The refusal is returned rather than thrown or swallowed, because the
     * sheet has to show the number — a refusal without one is just an obstacle.
     *
     * @return whether the palette was applied.
     */
    fun adoptColours(palette: ReaderPalette): Boolean {
        if (!palette.isReadable) return false
        _theme.value = _theme.value.adopting(palette)
        return true
    }

    /** Goes back to the preset's own colours, keeping its typography. */
    fun discardCustomColours() {
        _theme.value = _theme.value.discardingCustomColours()
    }

    /**
     * Turns publisher styles off by adopting a preset that overrides them.
     *
     * `reading-themes` requires an unavailable axis to offer "a single action that
     * turns publisher styles off", and to preserve the reading position when it
     * does. Readium re-lays out in place, so the position is kept by the navigator
     * rather than by anything here.
     */
    fun leavePublisherStyles() {
        if (_theme.value.preset.keepsPublisherStyles) adopt(ThemePreset.PAPER)
    }

    /**
     * Writes the theme back, so the next book on this shelf opens the way this one
     * was left.
     *
     * Collected rather than called from each mutator: there are seven of them, and one
     * that forgot to call would lose a reader's choice silently. Watching the flows
     * instead means an eighth mutator cannot forget — as the page-turn one did not have
     * to remember.
     *
     * ponytail: reads and rewrites the whole blob per change. A drag now emits ten
     * steps rather than one per frame, and the blob is a handful of small records, so
     * this is cheaper than a debounce would be to get right. Debounce it if a reader
     * with a thousand shelves ever notices.
     */
    private fun rememberThemeChanges() {
        val store = themeStore ?: return
        scope.launch {
            combine(_theme, _values, _transition) { theme, values, transition ->
                ShelfSettings(theme, values, transition)
            }
                .drop(1)
                .collect { store.save(store.themes().remembering(it, themeScope, shelf)) }
        }
    }

    init {
        rememberThemeChanges()
    }

    /** Nothing on screen while reading; one tap brings it back. */
    private val _isChromeVisible = MutableStateFlow(true)
    val isChromeVisible: StateFlow<Boolean> = _isChromeVisible.asStateFlow()

    fun toggleChrome() {
        _isChromeVisible.value = !_isChromeVisible.value
    }

    /**
     * Opens the book.
     *
     * Two steps, both Readium's: an `AssetRetriever` reaches the bytes, and a
     * `PublicationOpener` parses them. Our own `EpubReader` is not reused here —
     * the navigator needs Readium's own `Publication`, and parsing an EPUB twice to
     * avoid that would be worse than parsing it once each for two purposes.
     */
    suspend fun open(): Publication? = withContext(Dispatchers.IO) {
        val url: AbsoluteUrl? =
            if (location.startsWith("content://")) {
                Uri.parse(location).toAbsoluteUrl()
            } else {
                File(location).toUrl(isDirectory = false)
            }
        if (url == null) {
            _failure.value = application.getString(R.string.epub_failure_unreachable)
            return@withContext null
        }

        val httpClient = DefaultHttpClient()
        val assetRetriever = AssetRetriever(application.contentResolver, httpClient)
        val asset = assetRetriever.retrieve(url).getOrElse {
            _failure.value = application.getString(R.string.epub_failure_unreachable)
            return@withContext null
        }

        val opener = PublicationOpener(
            DefaultPublicationParser(
                context = application,
                httpClient = httpClient,
                assetRetriever = assetRetriever,
                // No PDF factory: a PDF opens in the comic reader, which renders it
                // with the platform's own `PdfRenderer`. Wiring a second PDF engine
                // in here would ship two.
                pdfFactory = null,
            ),
        )
        val publication = opener.open(asset, allowUserInteraction = false).getOrElse {
            _failure.value = application.getString(R.string.epub_failure_unreadable)
            return@withContext null
        }
        readingOrder = publication.readingOrder.map { it.href.toString() }
        _tableOfContents.value = publication.tableOfContents
        publication
    }

    /**
     * How far through the whole book, 0…1.
     *
     * The rule lives in `:core:model` so both platforms answer it the same way, and
     * because it is subtler than it looks: in scroll mode Readium reports `0.0` rather
     * than nothing, so trusting the report blindly leaves the reader at "0% read" for a
     * whole chapter. See [TotalProgression].
     *
     * `ebook-reader` allows an approximation: what it forbids is presenting a reflowable
     * *page number* as a stable identity. A percentage is explicitly the unit it asks
     * for.
     */
    private fun totalProgressionOf(locator: Locator): Double = TotalProgression.resolve(
        reported = locator.locations.totalProgression,
        within = locator.locations.progression ?: 0.0,
        resourceIndex = readingOrder.indexOf(locator.href.toString()),
        resourceCount = readingOrder.size,
    )

    /**
     * The stored position, turned back into a Readium `Locator`.
     *
     * Stored as the locator's own JSON rather than as a page number: `ebook-reader`
     * requires the position to survive a type-size change, and a page number
     * cannot. The progression is stored beside it so the library can draw a bar
     * without parsing anything.
     */
    suspend fun initialLocator(): Locator? {
        val record = progress?.progress(identity) ?: return null
        val position = record.position as? ReadingPosition.Reflowable ?: return null
        if (position.locator.isEmpty()) return null
        return runCatching { Locator.fromJSON(JSONObject(position.locator)) }.getOrNull()
    }

    /** Follows the navigator and writes every move down. */
    fun follow(locators: StateFlow<Locator>) {
        scope.launch {
            locators.collect { locator ->
                _chapterTitle.value = locator.title
                _currentResource.value = locator.href.removeFragment()
                val total = totalProgressionOf(locator)
                _progression.value = total
                record(locator, total)
            }
        }
    }

    /**
     * Writes the position down.
     *
     * Every move, not on leaving: ADR-0006 makes the local record authoritative,
     * and a reader that only saves on a clean exit loses the evening when the app
     * is killed in the background.
     */
    private suspend fun record(locator: Locator, total: Double) {
        val store = progress ?: return
        store.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Reflowable(
                    progression = total,
                    locator = locator.toJSON().toString(),
                ),
                // A book is finished at its end, and "the end" of a reflowable book
                // is the last of its content rather than a page number.
                isFinished = total >= 0.999,
                updatedAtEpochMillis = System.currentTimeMillis(),
            ),
        )
    }
}
