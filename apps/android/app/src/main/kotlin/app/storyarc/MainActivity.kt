package app.storyarc

import android.view.KeyEvent
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.designsystem.theme.VolumeTurns
import androidx.compose.runtime.CompositionLocalProvider
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
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.PublicationFormat
import app.storyarc.feature.epubreader.EpubReaderActivity
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.feature.library.CatalogueAcquisition
import app.storyarc.feature.library.CatalogueBrowser
import app.storyarc.feature.library.CatalogueBrowserScreen
import app.storyarc.feature.library.CatalogueConnection
import app.storyarc.feature.library.CataloguePage
import app.storyarc.feature.library.CatalogueSheet
import app.storyarc.feature.settings.SettingsScreen
import app.storyarc.feature.settings.BuildInfo
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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // `native-experience`: draw edge to edge and handle insets, rather than
        // avoiding them. Not optional on API 35+, and correct below it anyway.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A cold start from a file manager or a share sheet. Until this line existed the
        // system handed StoryArc a file and StoryArc showed its library instead.
        handedOver.value = OpenedFile.uriFrom(intent)

        // One store for the whole app. ADR-0006 makes the local record
        // authoritative, so the reader writing and the library reading have to be
        // the same store — two would disagree about where the user is.
        val progress = ProgressStore.open(applicationContext)
        val preferences = LibraryPreferences.open(applicationContext)
        val readerPreferences = ReaderPreferences.open(applicationContext)
        val settingsStore = SettingsStore.open(applicationContext)
        val sourceStore = SourceStore.open(applicationContext)
        val credentials = CredentialStore.open(applicationContext)
        val pinStore = CertificatePinStore.open(applicationContext)
        // One pin set for the whole app, loaded once. Shared between adding a catalogue
        // and browsing one on purpose: a certificate the reader accepted while adding a
        // server has to still be accepted when its covers load.
        val pins = CertificatePins(pinStore.pins())
        BuildInfo.read(applicationContext)

        setContent {
            // Read as state, so `settings-and-about`'s "applies immediately across
            // the whole app without a restart" is what the code does rather than
            // something it has to arrange: the theme recomposes because the value it
            // reads changed.
            var settings by remember { mutableStateOf(settingsStore.settings()) }

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
                            LibraryViewModel(application, progress, preferences, sourceStore)
                        }
                    },
                )

                // A page of a catalogue, pushed on top of the library. A list rather than
                // one value, because entering a section is another page and the back
                // gesture has to unwind them one at a time.
                var catalogue by remember { mutableStateOf<List<CataloguePage>>(emptyList()) }
                var isAddingCatalogue by remember { mutableStateOf(false) }

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
                val route: (Publication, String) -> Unit = { publication, path ->
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

                val page = catalogue.lastOrNull()
                if (page != null && selection == null && !isShowingSettings) {
                    BackHandler { catalogue = catalogue.dropLast(1) }
                    // Keyed on the address so entering a section builds a fresh browser
                    // rather than showing the previous page's entries.
                    val browser = remember(page.url) {
                        CatalogueBrowser(
                            applicationContext,
                            page.title,
                            page.url,
                            page.credential,
                            pins,
                        )
                    }
                    val acquisition = remember(page.url) {
                        CatalogueAcquisition(applicationContext, pins)
                    }
                    CatalogueBrowserScreen(
                        browser = browser,
                        acquisition = acquisition,
                        onEnter = { title, url ->
                            catalogue = catalogue + CataloguePage(title, url, page.credential)
                        },
                        // The same door a local publication goes through. A book fetched
                        // from a catalogue is a book.
                        onOpen = route,
                        onBack = { catalogue = catalogue.dropLast(1) },
                    )
                } else if (isShowingSettings) {
                    BackHandler { isShowingSettings = false }
                    val registry by libraryViewModel.registry.collectAsStateWithLifecycle()
                    SettingsScreen(
                        settings = settings,
                        readerStore = readerPreferences,
                        // The registry belongs to the library, and a feature module never
                        // depends on another feature module — so the app layer carries it
                        // across and carries the removal back.
                        sources = registry.sources,
                        itemCount = { libraryViewModel.itemCount(it.id) },
                        onRemoveSource = { libraryViewModel.removeSource(it) },
                        onRenameSource = { source, name ->
                            libraryViewModel.renameSource(source, name)
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
                        onClose = { isShowingSettings = false },
                    )
                } else if (selection == null) {
                    LibraryScreen(
                        viewModel = libraryViewModel,
                        onOpen = route,
                        onOpenSettings = { isShowingSettings = true },
                        onBrowse = { source ->
                            CataloguePage.of(source, credentials)?.let { catalogue = listOf(it) }
                        },
                        onAddCatalogue = { isAddingCatalogue = true },
                    )
                } else {
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
                        )
                    }
                    BackHandler { reading = null }
                    CompositionLocalProvider(LocalVolumeTurns provides volumeTurns) {
                        ReaderScreen(
                        viewModel = readerViewModel,
                        onClose = { reading = null },
                        preferences = readerPreferences,
                        // `comic-reader`: the end of one volume offers the next.
                        // The app layer answers this because it is the only place
                        // that can see both the reader and the library.
                        // Collected rather than read off the flow: a `.value` in a
                        // composition is a snapshot nothing recomposes on, so the
                        // end screen would offer whatever was there when the reader
                        // opened.
                        nextInSeries = LibraryIndex.next(selection.first, publications),
                        onOpenNext = { publication ->
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
