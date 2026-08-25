package app.storyarc.feature.epubreader

import android.app.Application
import android.net.Uri
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.setting
import app.storyarc.core.model.values
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
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
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

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

    /** Which preset is on and which axes have been moved from it. */
    private val _theme = MutableStateFlow(ReadingTheme())
    val theme: StateFlow<ReadingTheme> = _theme.asStateFlow()

    /** The typography in force: the preset's own values until an axis is moved. */
    private val _values = MutableStateFlow(ReadingTheme().preset.values)
    val values: StateFlow<ThemeValues> = _values.asStateFlow()

    /**
     * What Readium should render with, recomputed whenever either changes.
     *
     * Exposed rather than pushed: the activity owns the navigator and submits this
     * to it, which keeps the view model free of a Readium fragment.
     */
    val preferences get() = _theme.value.preferences(_values.value)

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
        publication
    }

    /**
     * How far through the whole book, 0…1.
     *
     * Readium fills in `totalProgression` only once it has computed a positions
     * list, which it does lazily and not at all for some publications. Without it
     * the reader would sit at "0% read" for a whole book, which is worse than an
     * approximation — so the fallback places the current resource in the reading
     * order and adds how far through that resource the reader is.
     *
     * `ebook-reader` allows this: what it forbids is presenting a reflowable *page
     * number* as a stable identity. A percentage is explicitly the unit it asks
     * for.
     */
    private fun totalProgressionOf(locator: Locator): Double {
        locator.locations.totalProgression?.let { return it }
        if (readingOrder.isEmpty()) return 0.0
        val index = readingOrder.indexOf(locator.href.toString()).takeIf { it >= 0 } ?: return 0.0
        val within = locator.locations.progression ?: 0.0
        return ((index + within) / readingOrder.size).coerceIn(0.0, 1.0)
    }

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
