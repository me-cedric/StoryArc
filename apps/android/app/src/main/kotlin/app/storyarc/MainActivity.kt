package app.storyarc

import android.view.KeyEvent
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.designsystem.theme.VolumeTurns
import androidx.compose.runtime.CompositionLocalProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storyarc.core.designsystem.theme.StoryArcTheme
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.feature.epubreader.EpubReaderActivity
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.AnnotationStore
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.ScanJournal
import app.storyarc.core.persistence.locationOf
import app.storyarc.core.persistence.RemovedDownload
import app.storyarc.core.persistence.finishedDownload
import app.storyarc.core.persistence.removeAfterFinishing
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.feature.library.CatalogueBrowser
import app.storyarc.feature.library.DownloadQueue
import app.storyarc.feature.library.CatalogueBrowserScreen
import app.storyarc.feature.library.CatalogueDetailScreen
import app.storyarc.feature.library.CatalogueConnection
import app.storyarc.feature.library.CataloguePage
import app.storyarc.feature.library.CatalogueSheet
import app.storyarc.feature.library.CollectionDetailScreen
import app.storyarc.feature.library.KavitaBrowserScreen
import app.storyarc.feature.library.KavitaCollectionScreen
import app.storyarc.feature.library.ServerList
import app.storyarc.feature.library.ServerShelf
import app.storyarc.feature.library.KavitaListScreen
import app.storyarc.feature.library.KavitaConnection
import app.storyarc.feature.library.KavitaLevel
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.KavitaSheet
import app.storyarc.feature.library.SmbBrowserScreen
import app.storyarc.feature.library.SmbConnection
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.smb.SmbReachability
import app.storyarc.feature.library.SmbLocator
import app.storyarc.feature.library.SmbPage
import app.storyarc.feature.library.SmbSheet
import app.storyarc.feature.library.KavitaSync
import app.storyarc.feature.library.ListPromoter
import app.storyarc.feature.library.ReadingListDetailScreen
import app.storyarc.feature.library.ShelvesScreen
import app.storyarc.feature.library.promote
import app.storyarc.feature.library.promotionOf
import app.storyarc.feature.library.withdrawList
import app.storyarc.feature.settings.SettingsScreen
import app.storyarc.feature.settings.BuildInfo
import app.storyarc.feature.library.SidebarDestination
import app.storyarc.feature.library.LibraryRail
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.feature.library.LibraryScreen
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.feature.reader.ReaderScreen
import app.storyarc.feature.reader.ReaderViewModel
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box

/** `offline-downloads`: "the removal is undoable for 10 seconds". */
private const val UNDO_WINDOW_MILLIS = 10_000L

/**
 * How long to keep looking for a publication a quick action named.
 *
 * `sources` restores the cached catalogue before it walks anything, so the usual answer
 * arrives in a frame or two. The cap is what stops a cold start with a slow share from
 * throwing the reader into a book five minutes after they asked for it, by which time they
 * are somewhere else. iOS's `ReadingContinuity` waits the same five seconds.
 */
private const val RESOLVE_ATTEMPTS = 20
private const val RESOLVE_INTERVAL_MILLIS = 250L

class MainActivity : ComponentActivity() {
    /**
     * Filled in by whichever reader is on screen, read by [onKeyDown].
     *
     * A volume key never reaches Compose: it arrives here, and only here can it be
     * consumed before the system changes the volume. `page-transitions` asks for the
     * volume buttons "where enabled in settings", so both halves have to be true — a
     * reader on screen *and* the setting on.
     */
    private val volumeTurns = VolumeTurns()

    /**
     * A file the system handed over, waiting for the composition to pick it up.
     *
     * A `MutableState` rather than a plain field, because the intent can arrive before the
     * first composition (a cold start from a file manager) or long after it
     * ([onNewIntent], when the app is already open). Both have to reach the same reader.
     */
    private val handedOver = mutableStateOf<Uri?>(null)

    /**
     * A quick action the launcher sent, waiting for the composition to pick it up.
     *
     * A `MutableState` for the same reason [handedOver] is one: the intent can arrive
     * before the first composition (the app was not running) or long after it
     * ([onNewIntent], when it was), and both have to reach the same handler.
     */
    private val quickAction = mutableStateOf<QuickActionRequest?>(null)

    /** Read on each key press rather than cached: the setting can change mid-session. */
    private val volumeTurnsEnabled: Boolean
        get() = SettingsStore.open(applicationContext).settings().turnPagesWithVolumeButtons

    /**
     * Volume keys, when a reader asked for them and the reader turned them on.
     *
     * Consumed rather than passed on, which is the whole point and also the risk: a reader
     * who cannot find why their volume keys stopped working has a defect, not a feature.
     * That is why the setting is off by default and says what it does.
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val forward = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> true
            KeyEvent.KEYCODE_VOLUME_UP -> false
            else -> return super.onKeyDown(keyCode, event)
        }
        val turn = volumeTurns.turn ?: return super.onKeyDown(keyCode, event)
        if (!volumeTurnsEnabled) return super.onKeyDown(keyCode, event)
        return turn(forward) || super.onKeyDown(keyCode, event)
    }

    /** The app was already open when the system handed a file over. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        OpenedFile.uriFrom(intent)?.let { handedOver.value = it }
        HomeScreenActions.requestFrom(intent)?.let { quickAction.value = it }
    }

    /**
     * The language this activity was built with.
     *
     * Kept so a change can be told from the value it already has: the composition reads the
     * setting on every launch, and recreating on that would be a loop.
     */
    private var language: String? = null

    /**
     * `localization`: the reader's own language, before anything reads a resource.
     *
     * Here rather than in the composition because a `Popup` -- every dropdown menu in the
     * app -- is its own window built from this context, and would otherwise stay in the
     * system's language while the screen behind it changed.
     */
    override fun attachBaseContext(newBase: Context) {
        language = newBase.chosenLanguage()
        super.attachBaseContext(newBase.speaking(language))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // `native-experience`: draw edge to edge and handle insets, rather than
        // avoiding them. Not optional on API 35+, and correct below it anyway.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A cold start from a file manager or a share sheet. Until this line existed the
        // system handed StoryArc a file and StoryArc showed its library instead.
        handedOver.value = OpenedFile.uriFrom(intent)
        // And the other kind of cold start: the reader held the app icon down and chose
        // an entry. `native-experience` asks for quick actions, and until this line the
        // launcher started the app and the choice was dropped on the floor.
        quickAction.value = HomeScreenActions.requestFrom(intent)

        // One store for the whole app. ADR-0006 makes the local record
        // authoritative, so the reader writing and the library reading have to be
        // the same store — two would disagree about where the user is.
        val progress = ProgressStore.open(applicationContext)
        val preferences = LibraryPreferences.open(applicationContext)
        val readerPreferences = ReaderPreferences.open(applicationContext)
        val settingsStore = SettingsStore.open(applicationContext)
        val sourceStore = SourceStore.open(applicationContext)
        val shelvesStore = ShelvesStore.open(applicationContext)
        val credentials = CredentialStore.open(applicationContext)
        val pinStore = CertificatePinStore.open(applicationContext)
        // One pin set for the whole app, loaded once. Shared between adding a catalogue
        // and browsing one on purpose: a certificate the reader accepted while adding a
        // server has to still be accepted when its covers load.
        val pins = CertificatePins(pinStore.pins())
        val downloadStore = DownloadStore.open(applicationContext)
        val kavitaProgress = KavitaProgressStore.open(applicationContext)
        // What an interrupted scan wrote down, so the next one picks up rather than starting
        // again. `local-library` requires a scan to be "cancellable and resumable".
        val scanJournal = ScanJournal.open(applicationContext)

        // How the reader reaches a share. Registered here because this is where the source
        // registry and the credential store both are; `core:format` stays unaware that SMB
        // exists, which is the only way that dependency can point.
        PublicationAccess.register("smb") { path ->
            val source = sourceStore.registry().sources
                .firstNotNullOfOrNull { candidate ->
                    SmbPage.of(candidate, credentials)?.takeIf {
                        path.startsWith(SmbLocator.of(it.address))
                    }
                }
                ?: error("no share holds ${'$'}path")
            val inside = path.removePrefix(SmbLocator.of(source.address)).trim('/')
            SmbClient(source.address).open(inside)
        }
        BuildInfo.read(applicationContext)

        setContent {
            // Read as state, so `settings-and-about`'s "applies immediately across
            // the whole app without a restart" is what the code does rather than
            // something it has to arrange: the theme recomposes because the value it
            // reads changed.
            var settings by remember { mutableStateOf(settingsStore.settings()) }

            // `localization`: a language chosen here is applied by rebuilding the activity
            // against it, because a composition local does not reach a menu -- see
            // `InterfaceLanguage`. Guarded on a real change so this does not fire on launch.
            LaunchedEffect(settings.language) {
                if (settings.language != language) recreate()
            }

            StoryArcTheme(appearance = settings.appearance, useDynamicColor = true) {
                // Provided here so both readers can fill it in, and so `onKeyDown` has
                // something to read. Volume-down turns forward, which is the convention
                // every reader app that offers this uses — down is "next", like a scroll.
                // The app layer owns navigation between features, because a
                // feature module never depends on another feature module
                // (docs/architecture). The library reports a choice; the reader
                // accepts one; neither knows the other exists.
                var reading by remember { mutableStateOf<Pair<Publication, String>?>(null) }
                var isShowingSettings by remember { mutableStateOf(false) }
                // Whether Settings should open straight at Downloads, because a quick
                // action asked for it rather than the reader tapping their way in.
                var isShowingDownloads by remember { mutableStateOf(false) }
                // A publication a quick action named, still waiting to be found.
                var wanted by remember { mutableStateOf<String?>(null) }
                // Re-read on the way in, so a download made while browsing a catalogue is on
                // this screen rather than one launch behind it.
                var downloads by remember { mutableStateOf(downloadStore.library()) }
                var removed by remember { mutableStateOf<RemovedDownload?>(null) }
                var refused by remember { mutableStateOf<OpenedFile.Outcome?>(null) }
                val selection = reading

                // A file the system handed over. Keyed on the `Uri` so a second file
                // opens, and cleared as soon as it is consumed so a rotation does not
                // reopen the last one.
                val incoming = handedOver.value
                LaunchedEffect(incoming) {
                    val uri = incoming ?: return@LaunchedEffect
                    handedOver.value = null
                    when (val outcome = OpenedFile.index(contentResolver, uri)) {
                        is OpenedFile.Outcome.Opened -> {
                            val publication = outcome.publication
                            // The same routing the library uses. A reflowable book goes to
                            // the EPUB reader and everything else to the comic reader,
                            // decided by what the publication is rather than by how it
                            // arrived.
                            if (publication.format == PublicationFormat.EPUB &&
                                !publication.isFixedLayout
                            ) {
                                startActivity(
                                    EpubReaderActivity.intent(
                                        this@MainActivity,
                                        outcome.decoderPath,
                                        publication.displayTitle,
                                        publication.series,
                                    ),
                                )
                            } else {
                                reading = publication to outcome.decoderPath
                            }
                        }
                        // Named, not swallowed. `local-library`: the app "names the format
                        // it detected and states which formats it supports, rather than
                        // reporting a generic failure".
                        else -> refused = outcome
                    }
                }

                refused?.let { outcome ->
                    RefusedFileDialog(outcome = outcome, onDismiss = { refused = null })
                }

                // Held across both branches, not just the library's: the reader's
                // end screen asks it what comes next in the series, and a model
                // created inside the library branch would not exist to ask.
                val libraryViewModel = viewModel<LibraryViewModel>(
                    factory = viewModelFactory {
                        initializer {
                            LibraryViewModel(
                                application,
                                progress,
                                preferences,
                                sourceStore,
                                shelvesStore,
                                // One store, two readers of it: what was downloaded joins
                                // the one library rather than being reachable only by
                                // browsing back to the server it came from, and imported
                                // copies live beside it -- see `ImportedCopies`.
                                downloadStore,
                                scanJournal,
                            )
                        }
                    },
                )

                // A page of a catalogue, pushed on top of the library. A list rather than
                // one value, because entering a section is another page and the back
                // gesture has to unwind them one at a time.
                var catalogue by remember { mutableStateOf<List<CataloguePage>>(emptyList()) }
                // The publication whose own screen is open, on top of the page it was chosen
                // from. Held here rather than in the browser so the back gesture unwinds the
                // detail first and the page behind it keeps its scroll and its entries.
                var chosen by remember { mutableStateOf<OpdsEntry?>(null) }
                var isAddingCatalogue by remember { mutableStateOf(false) }
                var isAddingKavita by remember { mutableStateOf(false) }
                var isAddingShare by remember { mutableStateOf(false) }
                var share by remember { mutableStateOf<SmbPage?>(null) }
                // A stack of folders, like the catalogue's: the browser leaves the
                // composition while a publication is open, so its position lives here.
                var sharePath by remember { mutableStateOf<List<String>>(emptyList()) }
                var kavita by remember { mutableStateOf<KavitaPage?>(null) }
                // Held beside the server rather than inside the browser, so closing a chapter
                // returns the reader to the series they were reading.
                var kavitaLevel by remember {
                    mutableStateOf<KavitaLevel>(KavitaLevel.Libraries)
                }
                var isShowingShelves by remember { mutableStateOf(false) }
                // Which grouping is open, if any. Two nullable ids rather than a sealed
                // type: only one can be open, and the back gesture unwinds them in order.
                var openCollection by remember { mutableStateOf<java.util.UUID?>(null) }
                var openList by remember { mutableStateOf<java.util.UUID?>(null) }
                var openServerShelf by remember { mutableStateOf<ServerShelf?>(null) }

                if (isAddingCatalogue) {
                    val connection = remember {
                        CatalogueConnection(applicationContext, pins, pinStore, credentials)
                    }
                    CatalogueSheet(
                        connection = connection,
                        onAdd = { libraryViewModel.addSource(it) },
                        onDismiss = {
                            isAddingCatalogue = false
                            connection.reset()
                        },
                    )
                }

                // Two readers, chosen by what the publication *is* rather than by a mode
                // the user picks. A reflowable book is laid out by a rendering engine
                // (ADR-0005); a comic is a list of images and needs none. A fixed-layout
                // EPUB is the third case and belongs with the comic reader.
                //
                // One rule, three callers: the library, a catalogue, and a file the system
                // handed over. Three copies of it is how one of them ends up wrong.
                if (isAddingKavita) {
                    val connection = remember { KavitaConnection(applicationContext, credentials) }
                    KavitaSheet(
                        connection = connection,
                        onAdd = { libraryViewModel.addSource(it) },
                        onDismiss = {
                            isAddingKavita = false
                            connection.reset()
                        },
                    )
                }

                if (isAddingShare) {
                    val connection = remember { SmbConnection(applicationContext, credentials) }
                    SmbSheet(
                        connection = connection,
                        onAdd = { libraryViewModel.addSource(it) },
                        onDismiss = {
                            isAddingShare = false
                            connection.reset()
                        },
                    )
                }

                val route: (Publication, String) -> Unit = { publication, path ->
                    // `native-experience` asks for continuity. Android has no Handoff and
                    // there is no backend to invent one with, so the honest mirror is to
                    // tell the system: the entry is pushed *and* reported as used, which is
                    // what lets the launcher rank it and the Assistant answer for it.
                    // Here rather than on a timer, because opening a book is the event.
                    HomeScreenActions.reportOpened(
                        this@MainActivity,
                        publication,
                        downloads.downloads.isNotEmpty(),
                    )
                    if (publication.format == PublicationFormat.EPUB && !publication.isFixedLayout) {
                        startActivity(
                            EpubReaderActivity.intent(
                                this@MainActivity,
                                path,
                                publication.displayTitle,
                                publication.series,
                            ),
                        )
                    } else {
                        reading = publication to path
                    }
                }

                val collectionOpen = openCollection
                val listOpen = openList
                val page = catalogue.lastOrNull()
                val server = kavita

                val serverLists by libraryViewModel.serverLists.collectAsStateWithLifecycle()
                val openShare = share
                val serverShelf = openServerShelf
                // Which source the reader is browsing, so the rail's indicator matches.
                var browsingSource by remember { mutableStateOf<java.util.UUID?>(null) }

                // One tap, three destinations, decided by what the source is. The reader
                // picked a place to browse, not a protocol.
                //
                // Named rather than written into `LibraryScreen`'s call, because the rail
                // opens the same three places and two copies of this is how one of them
                // ends up opening the wrong one.
                val browse: (Source) -> Unit = { source ->
                    browsingSource = source.id
                    CataloguePage.of(source, credentials)?.let {
                        chosen = null
                        catalogue = listOf(it)
                    }
                    KavitaPage.of(source, credentials)?.let {
                        kavita = it
                        kavitaLevel = KavitaLevel.Libraries
                    }
                    SmbPage.of(source, credentials)?.let {
                        share = it
                        sharePath = emptyList()
                    }
                }

                // `native-experience`: the launcher's own menu, published from the shelf
                // it describes. Republished whenever the list itself changes -- a reading
                // position moving, a download arriving -- so the entry a reader sees on
                // their home screen names the book they were last on.
                val continueReading by libraryViewModel.continueReading
                    .collectAsStateWithLifecycle()
                LaunchedEffect(continueReading.firstOrNull(), downloads.downloads.isNotEmpty()) {
                    // The activity's context, never the application's: `localization`
                    // lets the reader override the interface language, and that override
                    // lives on this activity -- see `InterfaceLanguage`. Published from
                    // the application context, every entry would be in the system's
                    // language while the app was in the reader's.
                    HomeScreenActions.publish(
                        this@MainActivity,
                        continueReading.firstOrNull(),
                        downloads.downloads.isNotEmpty(),
                    )
                }

                // What the reader chose from that menu. Cleared as soon as it is taken, so
                // a rotation does not act on it a second time.
                val chosenAction = quickAction.value
                LaunchedEffect(chosenAction) {
                    when (chosenAction) {
                        null -> Unit
                        is QuickActionRequest.ContinueReading -> {
                            quickAction.value = null
                            wanted = chosenAction.publicationId
                        }
                        // The entry promises the *shelf*, not wherever the reader last
                        // was, so everything stacked on top of the library comes off --
                        // the same unwinding the rail does for its own Library row.
                        QuickActionRequest.Library -> {
                            quickAction.value = null
                            reading = null
                            isShowingSettings = false
                            catalogue = emptyList()
                            chosen = null
                            kavita = null
                            share = null
                            openCollection = null
                            openList = null
                            openServerShelf = null
                            isShowingShelves = false
                        }
                        QuickActionRequest.Downloads -> {
                            quickAction.value = null
                            reading = null
                            downloads = downloadStore.library()
                            isShowingDownloads = true
                            isShowingSettings = true
                        }
                    }
                }

                // Waiting rather than looking, because a quick action lands on a cold
                // start: the shelf is still empty at the moment the request arrives.
                // Giving up is part of the behaviour rather than a failure of it -- the
                // reader lands on the library, which is where they would have landed.
                LaunchedEffect(wanted) {
                    val id = wanted ?: return@LaunchedEffect
                    repeat(RESOLVE_ATTEMPTS) {
                        val publication = libraryViewModel.publications.value
                            .firstOrNull { it.id == id }
                        if (publication != null) {
                            wanted = null
                            libraryViewModel.location(publication)
                                ?.let { route(publication, it) }
                            return@LaunchedEffect
                        }
                        kotlinx.coroutines.delay(RESOLVE_INTERVAL_MILLIS)
                    }
                    wanted = null
                }

                // Where the reader last went from the rail, so its indicator matches the
                // pane beside it. Derived from what is open rather than remembered on its
                // own: a back gesture that closes a browser has to un-light the item too,
                // and a second copy of the truth is how those two stop agreeing.
                val browsingSourceId = browsingSource
                val railSelection: SidebarDestination = when {
                    isShowingShelves || collectionOpen != null || listOpen != null ||
                        serverShelf != null -> SidebarDestination.Shelves
                    (openShare != null || server != null || page != null) &&
                        browsingSourceId != null -> SidebarDestination.OneSource(browsingSourceId)
                    else -> SidebarDestination.Library
                }

                // `native-experience`: a window with room for it "uses a multi-column
                // layout with a persistent sidebar". Persistent is the load-bearing word,
                // so the rail is wrapped around every browse-level screen rather than put
                // inside the library -- a sidebar that vanished the moment you followed
                // one of its own rows would be a menu, not navigation.
                //
                // Not beside the reader, which `comic-reader` gives the whole window, and
                // not beside Settings, which is a screen the reader comes back from.
                val windowClass = rememberWindowClass()
                val sourceRegistry by libraryViewModel.registry.collectAsStateWithLifecycle()
                Row(modifier = Modifier.fillMaxSize()) {
                    if (windowClass.showsSidebar && selection == null && !isShowingSettings) {
                        LibraryRail(
                            sources = sourceRegistry.sources,
                            selected = railSelection,
                            onSelect = { destination ->
                                // Every rail item lands on a top-level place, so whatever
                                // was stacked on top of the library is unwound first.
                                catalogue = emptyList()
                                kavita = null
                                share = null
                                openCollection = null
                                openList = null
                                openServerShelf = null
                                isShowingShelves = destination is SidebarDestination.Shelves
                                if (destination is SidebarDestination.OneSource) {
                                    sourceRegistry.sources
                                        .firstOrNull { it.id == destination.id }
                                        ?.let(browse)
                                }
                            },
                            onOpenSettings = {
                                downloads = downloadStore.library()
                                isShowingDownloads = false
                                isShowingSettings = true
                            },
                        )
                    }
                    Box(modifier = Modifier.weight(1f)) {
                    if (openShare != null && selection == null && !isShowingSettings) {
                        BackHandler {
                            if (sharePath.isEmpty()) share = null else sharePath = sharePath.dropLast(1)
                        }
                        SmbBrowserScreen(
                            title = openShare.title,
                            address = openShare.address,
                            path = sharePath.lastOrNull() ?: openShare.address.path,
                            onEnter = { sharePath = sharePath + it },
                            onOpen = route,
                            onBack = {
                                if (sharePath.isEmpty()) {
                                    share = null
                                } else {
                                    sharePath = sharePath.dropLast(1)
                                }
                            },
                        )
                    } else if (serverShelf != null && selection == null) {
                        BackHandler { openServerShelf = null }
                        if (serverShelf.isList) {
                            KavitaListScreen(
                                server = serverShelf.server,
                                listId = serverShelf.id,
                                title = serverShelf.title,
                                onOpen = route,
                                onBack = { openServerShelf = null },
                            )
                        } else {
                            KavitaCollectionScreen(
                                server = serverShelf.server,
                                collectionId = serverShelf.id,
                                title = serverShelf.title,
                                onOpenSeries = { each ->
                                    // Into the server browser, at that series: a collection is a
                                    // way in, not a separate place to read from.
                                    kavita = serverShelf.server
                                    kavitaLevel = KavitaLevel.Chapters(each)
                                    openServerShelf = null
                                },
                                onBack = { openServerShelf = null },
                            )
                        }
                    } else if (collectionOpen != null && selection == null) {
                        BackHandler { openCollection = null }
                        CollectionDetailScreen(
                            viewModel = libraryViewModel,
                            id = collectionOpen,
                            onOpen = route,
                            onBack = { openCollection = null },
                            onMark = { publication, isRead ->
                                libraryViewModel.mark(publication, isRead, kavitaProgress, credentials)
                            },
                        )
                    } else if (listOpen != null && selection == null) {
                        BackHandler { openList = null }
                        ReadingListDetailScreen(
                            viewModel = libraryViewModel,
                            id = listOpen,
                            onOpen = route,
                            onBack = { openList = null },
                            onMark = { publication, isRead ->
                                libraryViewModel.mark(publication, isRead, kavitaProgress, credentials)
                            },
                            // `collections-and-reading-lists` offers to copy a local list
                            // onto a server. The secrets a server asks for are the app
                            // layer's, so what the screen gets is what it can call.
                            promoter = ListPromoter(
                                plan = { list, server ->
                                    promotionOf(list, server, kavitaProgress)
                                },
                                copy = { list, server ->
                                    promote(list, server, kavitaProgress)
                                },
                                withdraw = { sourceId, listId ->
                                    libraryViewModel.withdrawList(sourceId, listId, credentials)
                                },
                            ),
                        )
                    } else if (isShowingShelves && selection == null) {
                        BackHandler { isShowingShelves = false }
                        val registry by libraryViewModel.registry.collectAsStateWithLifecycle()
                        ShelvesScreen(
                            viewModel = libraryViewModel,
                            onOpenCollection = { openCollection = it },
                            onOpenList = { openList = it },
                            onBack = { isShowingShelves = false },
                            servers = registry.sources.mapNotNull {
                                KavitaPage.of(it, credentials)
                            },
                            onOpenServerCollection = { server, id, title ->
                                openServerShelf = ServerShelf(server, id, title, isList = false)
                            },
                            onOpenServerList = { server, id, title ->
                                openServerShelf = ServerShelf(server, id, title, isList = true)
                            },
                        )
                    } else if (server != null && selection == null && !isShowingSettings) {
                        BackHandler { kavita = null }
                        KavitaBrowserScreen(
                            title = server.title,
                            address = server.address,
                            sourceId = server.id,
                            store = kavitaProgress,
                            progress = progress,
                            lists = serverLists,
                            level = kavitaLevel,
                            onLevel = { kavitaLevel = it },
                            onOpen = route,
                            onBack = { kavita = null },
                        )
                    } else if (page != null && selection == null && !isShowingSettings) {
                        // Keyed on the address so entering a section builds a fresh browser
                        // rather than showing the previous page's entries.
                        val browser = remember(page.url) {
                            CatalogueBrowser(
                                applicationContext,
                                page.title,
                                page.url,
                                page.credential,
                                pins,
                                page.origin,
                            )
                        }
                        val queue = remember(page.url) {
                            DownloadQueue(
                                applicationContext,
                                pins,
                                downloadStore,
                                credential = { page.credential },
                                origin = page.origin,
                            )
                        }
                        val entry = chosen
                        if (entry != null) {
                            BackHandler { chosen = null }
                            CatalogueDetailScreen(
                                entry = entry,
                                credential = page.credential,
                                client = browser.client,
                                queue = queue,
                                // The same door a local publication goes through. A book
                                // fetched from a catalogue is a book.
                                onOpen = route,
                                onBack = { chosen = null },
                            )
                        } else {
                            BackHandler { catalogue = catalogue.dropLast(1) }
                            CatalogueBrowserScreen(
                                browser = browser,
                                queue = queue,
                                onEnter = { title, url ->
                                    // The origin travels down, not the section's own address: a
                                    // section URL is one the server chose.
                                    catalogue = catalogue +
                                        CataloguePage(title, url, page.credential, page.origin)
                                },
                                onSelect = { chosen = it },
                                onBack = { catalogue = catalogue.dropLast(1) },
                            )
                        }
                    } else if (isShowingSettings) {
                        BackHandler { isShowingSettings = false }
                        val registry by libraryViewModel.registry.collectAsStateWithLifecycle()
                        SettingsScreen(
                            settings = settings,
                            readerStore = readerPreferences,
                            opensAtDownloads = isShowingDownloads,
                            // The registry belongs to the library, and a feature module never
                            // depends on another feature module — so the app layer carries it
                            // across and carries the removal back.
                            sources = registry.sources,
                            itemCount = { libraryViewModel.itemCount(it.id) },
                            onRemoveSource = { libraryViewModel.removeSource(it) },
                            onRenameSource = { source, name ->
                                libraryViewModel.renameSource(source, name)
                            },
                            onReorderSource = { source, later ->
                                libraryViewModel.reorderSource(source, later)
                            },
                            // Read from the store rather than from a browser's acquisition: the
                            // store is the record, and Settings can be reached without ever
                            // having opened a catalogue.
                            downloads = downloads,
                            bytesOnDisk = downloadStore.bytesOnDisk(),
                            onReorderDownload = { download, later ->
                                downloads = downloads.moving(download.id, later)
                                downloadStore.save(downloads)
                            },
                            onRemoveDownload = { download ->
                                // Asked of the store rather than composed here. The file is named
                                // after the publication and filed under its identifier, and this
                                // deleted `<id>/<id>.cbz` -- a path nothing has been written to
                                // since downloads started carrying the reader's own title.
                                downloadStore.delete(downloadStore.locationOf(download))
                                downloads = downloads.removing(download.id)
                                downloadStore.save(downloads)
                                // The library holds a row for every imported copy, and a row
                                // whose file has just been deleted is a book that opens onto
                                // nothing.
                                libraryViewModel.refreshImports()
                            },
                            onClearDownloads = {
                                // The bytes behind the ten-second undo are staged *inside* the
                                // downloads directory, so clearing already takes them with it.
                                // Dropping the pending removal is what stops the snackbar going
                                // on offering to restore a file that no longer exists — an undo
                                // that would put a record back for bytes nobody has, which is
                                // the "list that outlives its files" `DownloadStore` exists to
                                // prevent. No `settle()`: there is nothing left to delete.
                                removed = null
                                downloads = downloadStore.clearing()
                            },
                            // Written through on every change rather than on the way out.
                            // `settings-and-about` requires an appearance to apply
                            // immediately, and the state lives here so the theme above
                            // recomposes with it — the screen reports, the host holds.
                            onChange = {
                                settings = it
                                settingsStore.save(it)
                            },
                            onReset = {
                                // Both stores, and only what each one calls a setting. The
                                // reading *defaults* are settings; a theme chosen while
                                // reading is not, and neither is progress.
                                settingsStore.reset()
                                settings = settingsStore.settings()
                                readerPreferences.save(
                                    readerPreferences.themes().clearingDefaults(),
                                )
                            },
                            onClose = {
                                isShowingSettings = false
                                isShowingDownloads = false
                            },
                        )
                    } else if (selection == null) {
                        val publications by libraryViewModel.publications
                            .collectAsStateWithLifecycle()
                        // `offline-downloads`: a finished publication's download goes, and the
                        // reader has ten seconds to say otherwise. Swept here rather than in a
                        // reader's close path, because there are two readers and the EPUB one
                        // is a separate activity -- the library coming back is the one moment
                        // both of them pass through.
                        LaunchedEffect(settings.removeDownloadsAfterFinishing, publications) {
                            if (!settings.removeDownloadsAfterFinishing) return@LaunchedEffect
                            val target = finishedDownload(downloadStore, downloads) { path ->
                                progress.progress(PublicationIdentity(normalizedPath = path))
                                    ?.isFinished == true
                            } ?: return@LaunchedEffect
                            removeAfterFinishing(downloadStore, downloads, target.id)
                                ?.let { (without, taken) ->
                                    downloads = without
                                    removed?.settle()
                                    removed = taken
                                    launch {
                                        kotlinx.coroutines.delay(UNDO_WINDOW_MILLIS)
                                        if (removed === taken) {
                                            taken.settle()
                                            removed = null
                                        }
                                    }
                                }
                        }
                        LibraryScreen(
                            viewModel = libraryViewModel,
                            onOpen = route,
                            onOpenSettings = {
                                downloads = downloadStore.library()
                                isShowingDownloads = false
                                isShowingSettings = true
                            },
                            onBrowse = browse,
                            onAddCatalogue = { isAddingCatalogue = true },
                            onAddKavita = { isAddingKavita = true },
                            onAddShare = { isAddingShare = true },
                            onProbeSources = {
                                libraryViewModel.probeNetworkSources(credentials, pins)
                                // And keeps asking while anything is away, per `sources`'
                                // backoff. Stopped when the library leaves the screen, which is
                                // when nobody is looking at the answer.
                                libraryViewModel.retryUnreachableSources(credentials, pins)
                            },
                            onMark = { publication, isRead ->
                                libraryViewModel.mark(
                                    publication,
                                    isRead,
                                    kavitaProgress,
                                    credentials,
                                )
                            },
                            removedDownload = removed?.download?.title,
                            onUndoRemoval = {
                                lifecycleScope.launch {
                                    removed?.let { downloads = it.undo(downloads) }
                                    removed = null
                                }
                            },
                            onAddToServerList = { publication, list ->
                                libraryViewModel.addToServerList(
                                    publication,
                                    list,
                                    kavitaProgress,
                                    credentials,
                                )
                            },
                            onOpenShelves = { isShowingShelves = true },
                        )
                    } else {
                        val blockedSince by SmbReachability.blockedSince
                            .collectAsStateWithLifecycle()
                        val publications by libraryViewModel.publications.collectAsStateWithLifecycle()
                        // Keyed on the publication so opening a different one builds a
                        // fresh model rather than showing the previous book's pages.
                        val readerViewModel = remember(selection.first.id) {
                            ReaderViewModel(
                                selection.first,
                                contentResolver,
                                selection.second,
                                progress,
                                // The same store the ebook reader uses, and a different
                                // scope inside it: `reading-themes` gives comics and
                                // reflowable text separate defaults.
                                shelfStore = readerPreferences,
                                // And the same store the ebook reader marks into. A PDF
                                // that carries text is highlighted the same way a novel
                                // is, and `ebook-reader` lists both in one place.
                                annotationStore = AnnotationStore.open(this@MainActivity),
                            )
                        }
                        // Closing the reader is one moment `kavita-server` sends a position.
                        // Leaving for the home screen is the other, and the commoner one: a
                        // phone is usually closed by going home, and a position that only
                        // travelled on a clean exit would be the evening's reading lost.
                        val report: suspend () -> Unit = {
                            val publication = selection.first

                            val origin = kavitaProgress.origin(publication.id)
                            val page = progress.progress(publication.identity)?.position
                            if (origin != null && page is ReadingPosition.Page) {
                                KavitaSync.report(
                                    kavitaProgress,
                                    libraryViewModel.registry.value.sources
                                        .firstOrNull { it.id.toString() == origin.sourceId }
                                        ?.let { KavitaPage.of(it, credentials)?.address },
                                    origin,
                                    page.index,
                                )
                            }
                        }
                        val close: () -> Unit = {
                            reading = null
                            lifecycleScope.launch { report() }
                        }
                        val owner = LocalLifecycleOwner.current
                        DisposableEffect(owner) {
                            val watcher = LifecycleEventObserver { _, event ->
                                if (event == Lifecycle.Event.ON_STOP) {
                                    lifecycleScope.launch { report() }
                                }
                            }
                            owner.lifecycle.addObserver(watcher)
                            onDispose { owner.lifecycle.removeObserver(watcher) }
                        }
                        BackHandler { close() }
                        CompositionLocalProvider(LocalVolumeTurns provides volumeTurns) {
                            ReaderScreen(
                            viewModel = readerViewModel,
                            onClose = close,
                            blockedSince = blockedSince,
                            onDismissTrouble = { SmbReachability.clear() },
                            // Only for a publication that lives on a share. Everything else is
                            // already on the device, and offering to download it would be
                            // offering nothing.
                            onDownloadForOffline = selection.second
                                .takeIf { it.startsWith("smb://") }
                                ?.let { remote ->
                                    {
                                        lifecycleScope.launch {
                                            keepForOffline(
                                                downloadStore,
                                                selection.first,
                                                remote,
                                            )?.let { local -> reading = selection.first to local }
                                            SmbReachability.clear()
                                        }
                                    }
                                },
                            preferences = readerPreferences,
                            // `comic-reader`: the end of one volume offers the next.
                            // The app layer answers this because it is the only place
                            // that can see both the reader and the library.
                            // Collected rather than read off the flow: a `.value` in a
                            // composition is a snapshot nothing recomposes on, so the
                            // end screen would offer whatever was there when the reader
                            // opened.
                            // The library is what knows a reading list may have a different
                            // opinion about what comes next than the series does.
                            previousInSeries = libraryViewModel.previous(selection.first),
                            nextInSeries = libraryViewModel.next(selection.first),
                            onOpen = { publication ->
                                // The selection is replaced rather than a second reader
                                // pushed: stacking them would leave a pile behind a
                                // long series.
                                libraryViewModel.location(publication)?.let {
                                    reading = publication to it
                                }
                            },
                            )
                        }
                    }
                    }
                }
            }
        }
    }
}
