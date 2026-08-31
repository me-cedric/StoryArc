package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.removeAfterFinishing
import app.storyarc.feature.library.CatalogueBrowser
import app.storyarc.feature.library.CatalogueBrowserScreen
import app.storyarc.feature.library.CatalogueDetailScreen
import app.storyarc.feature.library.CataloguePage
import app.storyarc.feature.library.CollectionDetailScreen
import app.storyarc.feature.library.DownloadQueue
import app.storyarc.feature.library.KavitaBrowserScreen
import app.storyarc.feature.library.KavitaCollectionScreen
import app.storyarc.feature.library.KavitaLevel
import app.storyarc.feature.library.KavitaListScreen
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.ListPromoter
import app.storyarc.feature.library.OfflineSourceScreen
import app.storyarc.feature.library.PublicationDetailScreen
import app.storyarc.feature.library.ReadingListDetailScreen
import app.storyarc.feature.library.ServerShelf
import app.storyarc.feature.library.ShelvesScreen
import app.storyarc.feature.library.SmbBrowserScreen
import app.storyarc.feature.library.UnauthorizedSourceScreen
import app.storyarc.feature.library.promote
import app.storyarc.feature.library.promotionOf
import app.storyarc.feature.library.withdrawList
import app.storyarc.navigation.Screen
import kotlinx.coroutines.launch

/**
 * The screen on top of the current destination's path.
 *
 * One `when` over a sealed type, exhaustive by construction, with no `BackHandler` anywhere
 * in it: back is [app.storyarc.navigation.AppNavigation.back]'s answer alone, and every
 * screen's own back control is the same single call. That is the whole point of the
 * rewrite — a fifteenth screen cannot forget to answer a gesture it is never asked about.
 */
@Composable
internal fun HostedScreen(
    host: AppHost,
    screen: Screen,
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    onResetSettings: () -> Unit,
) {
    val dependencies = host.dependencies
    // Every screen's own back control is the same call the system gesture makes. Not "the
    // same behaviour" — the same rule, so the two cannot drift apart.
    val back = { host.navigate { back() } }
    // **Where `host.openPage` is not used, and why.** `publication-detail` puts a page
    // behind a cover "in the library, in a shelf, in search results or in a collection" —
    // the four surfaces that show the reader's own library. The three browse screens below
    // (a catalogue, a Kavita server, a shared folder) show somebody else's, and the
    // publication they hand over is built on the spot from the file they just fetched
    // rather than taken from the library. `PublicationDetailScreen` cannot place such a
    // publication — its own guard draws "this is gone" for anything the library does not
    // hold — so routing them here would put every remote book behind a page saying it does
    // not exist. Those paths keep their own detail screens, which `opds-catalog` and
    // `kavita-server` own, and open the book directly.
    when (screen) {
        is Screen.Catalogue -> CatalogueScreen(host, screen)

        is Screen.Kavita -> KavitaBrowserScreen(
            title = screen.page.title,
            address = screen.page.address,
            sourceId = screen.page.id,
            store = dependencies.kavitaProgress,
            progress = dependencies.progress,
            lists = host.library.serverLists.collectAsStateWithLifecycle().value,
            level = screen.level,
            // Each level is its own step on the path, so back walks chapters → series →
            // libraries → out, rather than leaving the server from whatever depth.
            onLevel = { level -> host.navigate { push(screen.copy(level = level)) } },
            searching = screen.search,
            onOpen = host.open,
            onBack = back,
        )

        is Screen.Share -> SmbBrowserScreen(
            title = screen.page.title,
            address = screen.page.address,
            path = screen.folder ?: screen.page.address.path,
            onEnter = { folder -> host.navigate { push(screen.copy(folder = folder)) } },
            onOpen = host.open,
            onBack = back,
        )

        is Screen.SourceAway -> OfflineSourceScreen(
            name = screen.source.displayName,
            onRetry = {
                host.library.testSource(screen.source, dependencies.credentials, dependencies.pins)
                back()
            },
            onBack = back,
        )

        is Screen.SourceRefused -> UnauthorizedSourceScreen(
            name = screen.source.displayName,
            isRefused = true,
            onBack = back,
        )

        Screen.Shelves -> {
            val registry by host.library.registry.collectAsStateWithLifecycle()
            ShelvesScreen(
                viewModel = host.library,
                onOpenCollection = { id -> host.navigate { push(Screen.Collection(id)) } },
                onOpenList = { id -> host.navigate { push(Screen.ReadingList(id)) } },
                onBack = back,
                servers = registry.sources.mapNotNull {
                    KavitaPage.of(it, dependencies.credentials)
                },
                onOpenServerCollection = { server, id, title ->
                    host.navigate {
                        push(Screen.ServerShelfPage(ServerShelf(server, id, title, isList = false)))
                    }
                },
                onOpenServerList = { server, id, title ->
                    host.navigate {
                        push(Screen.ServerShelfPage(ServerShelf(server, id, title, isList = true)))
                    }
                },
            )
        }

        is Screen.Collection -> CollectionDetailScreen(
            viewModel = host.library,
            id = screen.id,
            onOpen = host.openPage,
            onBack = back,
            onMark = { publication, isRead -> host.mark(publication, isRead) },
        )

        is Screen.ReadingList -> ReadingListDetailScreen(
            viewModel = host.library,
            id = screen.id,
            onOpen = host.openPage,
            onBack = back,
            onMark = { publication, isRead -> host.mark(publication, isRead) },
            // `collections-and-reading-lists` offers to copy a local list onto a server.
            // The secrets a server asks for are the app layer's, so what the screen gets is
            // what it can call.
            promoter = ListPromoter(
                plan = { list, server -> promotionOf(list, server, dependencies.kavitaProgress) },
                copy = { list, server -> promote(list, server, dependencies.kavitaProgress) },
                withdraw = { sourceId, listId ->
                    host.library.withdrawList(sourceId, listId, dependencies.credentials)
                },
            ),
        )

        is Screen.ServerShelfPage -> if (screen.shelf.isList) {
            KavitaListScreen(
                server = screen.shelf.server,
                listId = screen.shelf.id,
                title = screen.shelf.title,
                onOpen = host.open,
                onBack = back,
            )
        } else {
            KavitaCollectionScreen(
                server = screen.shelf.server,
                collectionId = screen.shelf.id,
                title = screen.shelf.title,
                onOpenSeries = { series ->
                    // Into the server browser, at that series: a collection is a way in,
                    // not a separate place to read from — so it takes the shelf's place on
                    // the path rather than stacking on top of it.
                    host.navigate {
                        replace(Screen.Kavita(screen.shelf.server, KavitaLevel.Chapters(series)))
                    }
                },
                onBack = back,
            )
        }

        is Screen.Settings -> SettingsHost(
            host = host,
            screen = screen,
            settings = settings,
            onSettingsChange = onSettingsChange,
            onResetSettings = onResetSettings,
            onClose = back,
        )

        is Screen.PublicationPage -> PublicationPage(host = host, screen = screen)

        is Screen.Reader -> ReaderHost(host = host, screen = screen, onClose = back)
    }
}

/**
 * The seam, wired to the rest of the app.
 *
 * The screen is deliberately ignorant of how a publication is fetched or opened — a feature
 * module never depends on another feature module, and this is the layer that knows a reader,
 * a download store and a keystore exist. What it hands down is four verbs and two facts.
 *
 * Download is offered only where the app can actually perform one: a publication whose
 * location is a remote address it can read. `publication-detail` asks for an action that
 * does not apply to be "absent, not shown disabled without explanation", so it arrives as
 * `null` rather than as a greyed row.
 */
@Composable
private fun PublicationPage(host: AppHost, screen: Screen.PublicationPage) {
    val publication = screen.publication
    val downloads by host.downloads
    val scope = rememberCoroutineScope()
    val record = downloads[publication.id]
    val isDownloaded = record?.state == Download.State.Finished
    // A file in a folder the reader gave the app is already here; only a publication that
    // came from somewhere else has to be fetched to be on the device.
    val location = host.library.location(publication)
    val isRemote = location != null && PublicationAccess.isRemote(location)
    val isOnDevice = isDownloaded || (location != null && !isRemote)

    PublicationDetailScreen(
        publication = publication,
        viewModel = host.library,
        isOnDevice = isOnDevice,
        downloadFraction = record?.takeIf { it.state != Download.State.Finished }?.fraction?.toFloat(),
        onRead = { chosen ->
            val path = host.library.location(chosen) ?: return@PublicationDetailScreen
            host.open(chosen, path)
        },
        // A cover leads to a page, and a page's series shelf leads to more pages. The same
        // verb every other cover in the app takes, so the guard against pushing a second
        // copy of the page the reader is already on applies here too.
        onOpenPage = host.openPage,
        onMark = { chosen, isRead -> host.mark(chosen, isRead) },
        onDownload = if (isRemote && !isDownloaded) {
            {
                scope.launch {
                    keepForOffline(host.dependencies.downloads, publication, location)
                    host.downloads.value = host.dependencies.downloads.library()
                }
            }
        } else {
            null
        },
        // Reversible, through the same helper the finished-publication sweep uses: the
        // bytes are moved aside rather than deleted, and the Downloads destination's undo
        // banner is already watching `host.removed` for exactly this.
        onRemoveDownload = if (isDownloaded) {
            {
                scope.launch {
                    removeAfterFinishing(
                        host.dependencies.downloads,
                        host.downloads.value,
                        publication.id,
                    )?.let { (library, removal) ->
                        host.downloads.value = library
                        host.removed.value = removal
                    }
                }
            }
        } else {
            null
        },
        onBack = { host.navigate { back() } },
    )
}

/**
 * Marking read or unread. The app layer owns the secrets a server may ask for, so a screen
 * reports the reader's choice and this is what can carry it across.
 */
private fun AppHost.mark(publication: Publication, isRead: Boolean) {
    library.mark(publication, isRead, dependencies.kavitaProgress, dependencies.credentials)
}

/**
 * A page of an online library, and the publication chosen from it.
 *
 * The browser and its download queue are remembered on the page's address, and the chosen
 * publication rides on the same screen value — so opening one and closing it again returns
 * to a page that still holds its entries and its scroll, without a second HTTP client being
 * built for the same catalogue.
 */
@Composable
private fun CatalogueScreen(host: AppHost, screen: Screen.Catalogue) {
    val page: CataloguePage = screen.page
    val dependencies = host.dependencies
    val context = host.activity.applicationContext
    // Keyed on the address so entering a section builds a fresh browser rather than showing
    // the previous page's entries.
    val browser = remember(page.url) {
        CatalogueBrowser(context, page.title, page.url, page.credential, dependencies.pins, page.origin)
    }
    val queue = remember(page.url) {
        DownloadQueue(
            context,
            dependencies.pins,
            dependencies.downloads,
            credential = { page.credential },
            origin = page.origin,
        )
    }
    val entry = screen.entry
    if (entry != null) {
        CatalogueDetailScreen(
            entry = entry,
            credential = page.credential,
            client = browser.client,
            queue = queue,
            // The same door a local publication goes through. A book fetched from an online
            // library is a book.
            onOpen = host.open,
            onBack = { host.navigate { back() } },
        )
    } else {
        CatalogueBrowserScreen(
            browser = browser,
            queue = queue,
            onEnter = { title, url ->
                // The origin travels down, not the section's own address: a section URL is
                // one the server chose.
                host.navigate {
                    push(Screen.Catalogue(CataloguePage(title, url, page.credential, page.origin)))
                }
            },
            // Replaced rather than pushed: the chosen publication is a state of this page,
            // not a position of its own. `Screen.Catalogue.previous` is what makes back out
            // of it land here, with the browser still holding its entries.
            onSelect = { chosen -> host.navigate { replace(screen.copy(entry = chosen)) } },
            onBack = { host.navigate { back() } },
        )
    }
}
