package app.storyarc

import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.storyarc.core.designsystem.back.PredictiveBack
import app.storyarc.core.designsystem.back.PredictiveBackHost
import app.storyarc.core.designsystem.navigation.AdaptiveNavigationShell
import app.storyarc.core.designsystem.navigation.NavigationEntry
import app.storyarc.core.designsystem.navigation.RailMenuLabels
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.persistence.RemovedDownload
import app.storyarc.feature.epubreader.EpubReaderActivity
import app.storyarc.feature.library.CataloguePage
import app.storyarc.feature.library.KavitaLevel
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.feature.library.SmbPage
import app.storyarc.feature.settings.BuildInfo
import app.storyarc.feature.settings.WhatsNew
import app.storyarc.feature.settings.WhatsNewRelease
import app.storyarc.feature.settings.WhatsNewSheet
import app.storyarc.feature.settings.WhatsNewStore
import app.storyarc.navigation.AppDestination
import app.storyarc.navigation.AppNavigation
import app.storyarc.navigation.AppSheet
import app.storyarc.navigation.Screen

/**
 * The frame the whole app draws inside.
 *
 * Three destinations in Material's own adaptive navigation, one typed stack of screens per
 * destination, and **one** back rule. What this replaces was a chain of fourteen booleans
 * and nullables in which each branch installed its own `BackHandler` — so "what does back
 * do" had fourteen answers that had to agree, and a rail whose selected item was re-derived
 * from whichever of four nullables happened to be set.
 *
 * **Search is the fourth destination**, and this comment used to say the opposite: that
 * Material ranks a search bar above a search destination and permits the destination only
 * for an app whose primary action is searching. Material does say that, and the judgement it
 * conditions is ours — StoryArc's publications arrive from a device, a folder, an OPDS
 * catalogue, a Kavita server and an SMB share, and no shelf shows all of them at once in a
 * way a reader can scan. Search is the only surface that spans the sources, so in this app it
 * is the way in rather than a filter. `quiet-shell-and-search`'s `design.md` sets the
 * argument out in full.
 */
@Composable
internal fun AppShell(
    activity: ComponentActivity,
    dependencies: AppDependencies,
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    onResetSettings: () -> Unit,
    /** A file the system handed over, waiting for the composition to pick it up. */
    handedOver: MutableState<Uri?>,
    /** A quick action the launcher sent, waiting for the same. */
    quickAction: MutableState<QuickActionRequest?>,
) {
    var navigation by rememberSaveable(stateSaver = AppNavigation.Saver) {
        mutableStateOf(AppNavigation())
    }
    var sheet by remember { mutableStateOf<AppSheet?>(null) }

    // What changed in the version just installed, if this launch is the one that says so.
    //
    // `settings-and-about`: shown "once, after it has been updated", never on a first ever
    // launch, and never twice for one version. All three are `WhatsNew.onLaunch`'s answer,
    // and it is asked **inside `remember`'s initial value**: the version is recorded by the
    // same call that decides, so a reader who swipes the sheet away — or one who never sees
    // it because the version had nothing to say — is recorded either way. There is no path
    // through this that shows the screen without recording it, which is the requirement
    // stated as "the seen flag is written when the screen is shown, not when it is
    // dismissed".
    var whatsNew by remember {
        mutableStateOf<WhatsNewRelease?>(
            WhatsNew.onLaunch(
                installed = BuildInfo.version,
                store = WhatsNewStore.open(activity.applicationContext),
            ),
        )
    }
    var refusedFile by remember { mutableStateOf<OpenedFile.Outcome?>(null) }

    // Re-read on the way in, so a download made while browsing an online library is on this
    // screen rather than one launch behind it.
    val downloads = remember { mutableStateOf(dependencies.downloads.library()) }
    val removed = remember { mutableStateOf<RemovedDownload?>(null) }

    // Held across every destination, not inside the library's: the reader's end screen asks
    // it what comes next in the series, and a model created inside one branch would not
    // exist to ask.
    val library = viewModel<LibraryViewModel>(
        factory = viewModelFactory {
            initializer {
                LibraryViewModel(
                    activity.application,
                    dependencies.progress,
                    dependencies.libraryPreferences,
                    dependencies.sources,
                    dependencies.shelves,
                    // One store, two readers of it: what was downloaded joins the one
                    // library rather than being reachable only by browsing back to the
                    // server it came from, and imported copies live beside it.
                    dependencies.downloads,
                    dependencies.scanJournal,
                    dependencies.kavitaCards,
                )
            }
        },
    )

    val host = AppHost(
        activity = activity,
        dependencies = dependencies,
        library = library,
        downloads = downloads,
        removed = removed,
        navigate = { navigation = it(navigation) },
        open = { publication, path ->
            // `native-experience` asks for continuity. Android has no Handoff and there is
            // no backend to invent one with, so the honest mirror is to tell the system:
            // the entry is pushed *and* reported as used, which is what lets the launcher
            // rank it and the Assistant answer for it. Here rather than on a timer, because
            // opening a book is the event.
            HomeScreenActions.reportOpened(
                activity,
                publication,
                downloads.value.downloads.isNotEmpty(),
            )
            // Two readers, chosen by what the publication *is* rather than by a mode the
            // reader picks. A reflowable book is laid out by a rendering engine (ADR-0005);
            // a comic is a list of images and needs none. A fixed-layout EPUB is the third
            // case and belongs with the comic reader.
            if (publication.format == PublicationFormat.EPUB && !publication.isFixedLayout) {
                activity.startActivity(
                    EpubReaderActivity.intent(
                        activity,
                        path,
                        publication.displayTitle,
                        publication.series,
                    ),
                )
            } else {
                // Replaced rather than stacked when a reader is already open: the next
                // volume offered at the end of one would otherwise leave a pile of readers
                // behind a long series.
                val reader = Screen.Reader(publication, path)
                navigation = if (navigation.current is Screen.Reader) {
                    navigation.replace(reader)
                } else {
                    navigation.push(reader)
                }
            }
        },
        openPage = { publication -> navigation = navigation.openPage(publication) },
        browse = { source, term ->
            // One tap, three kinds of place, decided by what the source is. The reader
            // picked somewhere to browse, not a protocol.
            navigation = when {
                // A source that is not answering is not opened into a browser that will
                // fail: it would fetch, wait, and land on an empty list with nothing to say
                // why. `sources` promises "cached contents remain browsable", and for a
                // server there are none — saying so is the honest thing besides.
                source.state is SourceConnectionState.Unreachable ->
                    navigation.push(Screen.SourceAway(source))
                // `kavita-server`: a revoked key marks the source unauthorized "with an
                // explanation and an action to enter a new key". The key is still in the
                // keystore, so a page can be built, so without this the browser opened and
                // every request in it failed in silence.
                source.state is SourceConnectionState.Unauthorized ->
                    navigation.push(Screen.SourceRefused(source))
                else -> {
                    val credentials = dependencies.credentials
                    val page: Screen? =
                        CataloguePage.of(source, credentials)?.let { Screen.Catalogue(it) }
                            ?: KavitaPage.of(source, credentials)
                                ?.let { Screen.Kavita(it, KavitaLevel.Libraries, term) }
                            ?: SmbPage.of(source, credentials)?.let { Screen.Share(it) }
                    if (page == null) navigation else navigation.push(page)
                }
            }
        },
        sheet = { sheet = it },
    )

    AppIntents(
        host = host,
        settings = settings,
        handedOver = handedOver,
        quickAction = quickAction,
        isReading = navigation.current is Screen.Reader,
        onRefusedFile = { refusedFile = it },
    )

    refusedFile?.let { outcome ->
        // Named, not swallowed. `local-library`: the app "names the format it detected and
        // states which formats it supports, rather than reporting a generic failure".
        RefusedFileDialog(outcome = outcome, onDismiss = { refusedFile = null })
    }

    AdaptiveNavigationShell(
        entries = AppDestination.entries.map { destination ->
            NavigationEntry(
                label = stringResource(destination.label),
                icon = destination.icon,
                selected = navigation.destination == destination,
                onSelect = { navigation = navigation.select(destination) },
            )
        },
        menu = RailMenuLabels(
            expand = stringResource(R.string.rail_expand),
            collapse = stringResource(R.string.rail_collapse),
        ),
        // Only the opened rail draws these. The library's own top bar carries Shelves and
        // Settings on a narrow window and deliberately drops both once the window is wide
        // enough for side navigation — so without them here, a tablet reader could reach
        // neither.
        secondaryEntries = listOf(
            NavigationEntry(
                label = stringResource(R.string.destination_shelves),
                icon = Icons.Filled.Inventory2,
                selected = navigation.current is Screen.Shelves,
                onSelect = {
                    // Choosing the entry a reader is already on is not a second copy of it.
                    if (navigation.current !is Screen.Shelves) {
                        navigation = navigation.push(Screen.Shelves)
                    }
                },
            ),
            NavigationEntry(
                label = stringResource(R.string.destination_settings),
                icon = Icons.Filled.Settings,
                // Never selected: Settings is a screen the reader comes back from rather
                // than a place they stay in, and an indicator left on it would be claiming
                // the library was somewhere else.
                selected = false,
                onSelect = {
                    downloads.value = dependencies.downloads.library()
                    navigation = navigation.push(Screen.Settings())
                },
            ),
        ),
        showsNavigation = navigation.showsNavigation,
    ) {
        // `native-experience` asks for predictive back, and the manifest opt-in is only the
        // half the system can do for itself: it draws the way out of the *app*. Everything
        // inside the app is this navigation value, so the preview of one of its screens
        // leaving is the app's own to draw — and until this host existed the handler below
        // was a plain `BackHandler` that reported only that the gesture had finished.
        //
        // Around the navigation area rather than around the whole shell, because back never
        // takes the navigation control away: it pops a screen off the current destination's
        // path, or returns to the destination the app opens on. The screen is what leaves;
        // the bar or the rail is what stays, and shrinking it with the screen would preview
        // an exit that is not going to happen.
        //
        // Settings keeps its own host inside this one. The composition local is static, so
        // the innermost host owns the handlers below it and each transform is applied
        // exactly once — nesting is the arrangement, not a conflict.
        PredictiveBackHost {
            // The one back rule. Registered before the content so that a modal or a screen
            // with its own handler wins over it, which is what those handlers are for;
            // everything else falls through to here.
            PredictiveBack(enabled = navigation.canGoBack) { navigation = navigation.back() }

            // One column, or a shelf and a page side by side where the window has room for
            // both. Which of the two is derived from this same navigation — see `AppPanes`.
            AppContent(
                host = host,
                navigation = navigation,
                settings = settings,
                onSettingsChange = onSettingsChange,
                onResetSettings = onResetSettings,
            )
        }
    }

    AppSheets(host = host, sheet = sheet)

    // Over whatever the reader landed on, and never blocking: one action dismisses it, the
    // scrim dismisses it, and back dismisses it. Nothing waits on it and nothing is lost by
    // ignoring it. A `ModalBottomSheet` rather than a full-screen dialog — see
    // `WhatsNewSheet`, which carries Material's own reason and the tablet it turns on.
    whatsNew?.let { release ->
        WhatsNewSheet(release = release, onDismiss = { whatsNew = null })
    }
}

/** What the navigation control calls each destination. Never an icon alone. */
private val AppDestination.label: Int
    get() = when (this) {
        AppDestination.HOME -> R.string.destination_home
        AppDestination.LIBRARY -> R.string.destination_library
        AppDestination.DOWNLOADS -> R.string.destination_downloads
        AppDestination.SEARCH -> R.string.destination_search
    }

private val AppDestination.icon: ImageVector
    get() = when (this) {
        AppDestination.HOME -> Icons.Filled.Home
        AppDestination.LIBRARY -> Icons.AutoMirrored.Filled.MenuBook
        AppDestination.DOWNLOADS -> Icons.Filled.Download
        AppDestination.SEARCH -> Icons.Filled.Search
    }
