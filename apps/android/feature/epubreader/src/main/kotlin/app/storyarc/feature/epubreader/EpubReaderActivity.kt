package app.storyarc.feature.epubreader

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
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
        private const val NAVIGATOR_TAG = "epub-navigator"

        /**
         * @param location where the book lives, as the library recorded it: a
         *   filesystem path, or a `content://` URI from a folder the user picked.
         */
        fun intent(context: Context, location: String, title: String): Intent =
            Intent(context, EpubReaderActivity::class.java)
                .putExtra(EXTRA_LOCATION, location)
                .putExtra(EXTRA_TITLE, title)
    }

    private val model: EpubReaderViewModel by lazy {
        EpubReaderViewModel(
            application = application,
            location = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
            identity = PublicationIdentity(
                normalizedPath = requireNotNull(intent.getStringExtra(EXTRA_LOCATION)),
            ),
            progress = ProgressStore.open(applicationContext),
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

                    EpubChrome(
                        title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
                        chapter = chapter,
                        progression = progression,
                        failure = failure,
                        isVisible = isVisible,
                        onClose = { finish() },
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
    }
}
