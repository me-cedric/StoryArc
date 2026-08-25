package app.storyarc.feature.epubreader

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.activity.compose.setContent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.ui.platform.ComposeView
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import androidx.fragment.app.commitNow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.designsystem.theme.AppearanceMode
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ReaderPreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.ExperimentalReadiumApi

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
            series = intent.getStringExtra(EXTRA_SERIES),
        )
    }

    private lateinit var container: FragmentContainerView

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
                    val brightness by model.brightness.collectAsStateWithLifecycle()
                    var isShowingTheme by remember { mutableStateOf(false) }

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
                    LaunchedEffect(theme, values) { applyTheme() }

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
                            onDismiss = { isShowingTheme = false },
                        )
                    }

                    EpubChrome(
                        title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
                        chapter = chapter,
                        progression = progression,
                        failure = failure,
                        isVisible = isVisible,
                        onClose = { finish() },
                        onOpenTheme = { isShowingTheme = true },
                    )
                }
            }
        }

        setContentView(
            FrameLayout(this).apply {
                addView(container)
                addView(chrome)
            },
        )

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
        )
    }
}
