package app.storyarc.feature.reader

import android.content.ComponentCallbacks2
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.MemoryPressure
import app.storyarc.core.model.Publication
import kotlinx.coroutines.delay

/**
 * The paged comic reader.
 *
 * `comic-reader` lists five transition modes. This is **slide**, the one that needs
 * no shader — page curl and continuous scroll belong to the
 * `reader-theming-and-page-transitions` change, whose Phase 0 spikes decide how the
 * curl is drawn on each platform. Building one here would pre-empt that decision.
 *
 * What is here is what every mode shares: page order, reading direction, fit, zoom,
 * and chrome that gets out of the way. Fit *modes* — fit-to-width, fit-to-height,
 * original size — are not here yet; the reader fits the whole page and zoom starts
 * from that.
 *
 * iOS's `ReaderView` is the same reader with `TabView` in place of `HorizontalPager`
 * and a `UIScrollView` in place of the transformable modifier.
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onClose: () -> Unit,
    /**
     * What surrounds this publication in its series, and how to open one of them.
     * Supplied by the app layer: the reader does not know what a library is, and a
     * feature module never depends on another feature module.
     *
     * `comic-reader` asks for previous and next chapter actions "without returning to
     * the library", and one publication of a series is what a chapter is here — so the
     * same two neighbours answer both the chapter buttons and the end screen.
     */
    previousInSeries: Publication? = null,
    nextInSeries: Publication? = null,
    onOpen: (Publication) -> Unit = {},
    /** `null` for a publication that was never a download. See [DownloadCleanupOffer]. */
    downloadCleanup: DownloadCleanupOffer? = null,
    onDismissTrouble: () -> Unit = {},
    onDownloadForOffline: (suspend () -> Boolean)? = null,
    modifier: Modifier = Modifier,
) {
    val pages by viewModel.pages.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()
    val isWaitingForDownload by viewModel.isWaitingForDownload.collectAsStateWithLifecycle()
    val isOpened by viewModel.isOpened.collectAsStateWithLifecycle()

    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val maxPixelSize = with(density) {
        maxOf(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp).roundToPx()
    }

    // Keyed on the model, not on `Unit`. The end screen swaps in the next issue
    // without leaving this composable, so an effect that runs once would open the
    // first publication and then show a spinner for ever on the second.
    LaunchedEffect(viewModel) { viewModel.open(maxPixelSize) }
    SmbNetworkWatchEffect()
    PageRecoveryEffect(viewModel)
    ReaderBrightnessEffect(viewModel.brightness.collectAsStateWithLifecycle().value)

    // `comic-reader`: "the screen does not auto-lock while a page is visible, and
    // normal locking resumes on leaving". A long look at one page is reading, not
    // idling. On the view rather than the window flag, so leaving the screen
    // restores the device's own behaviour without the reader having to remember to.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    // `reading-themes`: a custom background "applies to the area around the page and not
    // to the page itself, because tinting artwork is not a reading preference". This is
    // that area, and black is what it is until a reader says otherwise.
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val matte = remember(settings) { matteColour(settings.theme.custom?.background) }

    // `comic-reader`: the fit choice persists per series, so it is read from the shelf
    // rather than held here — the same place the transition, the direction, the axis, the
    // adjustments, the spread offset and the separator are all kept.
    val fit = settings.fit

    Box(
        modifier = modifier.fillMaxSize().background(matte),
        contentAlignment = Alignment.Center,
    ) {
        when {
            failure != null -> {
                val shown = failure!!
                Message(stringResource(shown.textRes, *shown.args.toTypedArray()))
                CloseButton(onClose)
            }
            isWaitingForDownload -> {
                WaitingForDownload()
                CloseButton(onClose)
            }
            pages.isEmpty() && isOpened -> {
                Message(stringResource(R.string.reader_empty))
                CloseButton(onClose)
            }
            pages.isEmpty() -> {
                DelayedProgressIndicator()
                CloseButton(onClose)
            }
            else -> Pager(
                viewModel = viewModel,
                pages = pages,
                onClose = onClose,
                previousInSeries = previousInSeries,
                nextInSeries = nextInSeries,
                onOpen = onOpen,
                downloadCleanup = downloadCleanup,
                fit = fit,
                onFitChange = viewModel::chooseFit,
                matte = matte,
            )
        }

        // Over the page rather than in place of it: `network-share` requires pages already
        // read to stay readable while the network is away.
        NetworkNotice(
            blockedSince = viewModel.pageBlockedSince,
            onDismiss = onDismissTrouble,
            onDownload = onDownloadForOffline,
            onLeave = onClose,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.CloseButton(onClose: () -> Unit) {
    IconButton(
        onClick = onClose,
        modifier = Modifier.align(Alignment.TopStart).padding(StoryArcSpace.md),
    ) {
        // Scrim, not a 20% white pill: the chrome draws straight onto the page art, and
        // over a white manga page a white icon on a white pill measured 1:1.
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = stringResource(R.string.reader_close),
                tint = Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/**
 * A spinner that waits before it appears.
 *
 * `comic-reader`: "a progress indicator appears only after 400 ms". A page that
 * decodes in 30 ms should not flash a spinner on its way — the flash reads as a
 * stutter, which is the opposite of what the indicator is for.
 */
@Composable
internal fun DelayedProgressIndicator() {
    var isVisible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(SPINNER_DELAY_MILLIS)
        isVisible = true
    }
    if (isVisible) CircularProgressIndicator(color = Color.White)
}

@Composable
internal fun Message(text: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier.padding(StoryArcSpace.gutter),
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = Color.White.copy(alpha = 0.7f))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * The colour behind the page.
 *
 * A comic is read against its own artwork, so black is the default and a *preset* never
 * reaches here — a preset is a typographic theme and its paper colour means nothing behind
 * a page of art. Only a colour the reader chose explicitly applies, which is what
 * `reading-themes` means by "the area around the page and not the page itself".
 */
internal fun matteColour(hex: String?): Color {
    val text = hex?.removePrefix("#") ?: return Color.Black
    val value = text.toLongOrNull(16) ?: return Color.Black
    return Color(
        red = ((value shr 16) and 0xFF) / 255f,
        green = ((value shr 8) and 0xFF) / 255f,
        blue = (value and 0xFF) / 255f,
    )
}

/**
 * What one of Android's seven trim levels means in the three states the reader knows.
 *
 * `TRIM_MEMORY_RUNNING_CRITICAL` and everything above it — including the levels raised
 * once the app is no longer in front — are the ones where the system is choosing what to
 * end. `RUNNING_MODERATE` and `RUNNING_LOW` are a request rather than a threat.
 *
 * The running levels are deprecated as of API 35, which stopped delivering them, and are
 * still what an API 31 to 34 device sends — and ADR-0003 puts the floor at 31. So they
 * are read rather than ignored, and a device that never sends them simply never narrows
 * the window until its UI is hidden.
 *
 * iOS's `MemoryPressureSource` maps the same three states out of a dispatch source.
 */
@Suppress("DEPRECATION")
internal fun trimPressure(level: Int): MemoryPressure = when {
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> MemoryPressure.CRITICAL
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> MemoryPressure.WARNING
    else -> MemoryPressure.NORMAL
}

private const val SPINNER_DELAY_MILLIS = 400L
