package app.storyarc

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.ReadingProgress
import app.storyarc.feature.library.HomeScreen
import app.storyarc.feature.library.HomeSection
import app.storyarc.feature.library.HomeShelves
import app.storyarc.feature.library.HomeSurface

/**
 * The reading room — the surface the app opens on.
 *
 * The app layer's half of Home: it gathers what the surface is made of and answers the two
 * questions the presentation cannot. Everything it reads is local — the publications the
 * library already holds, the reading positions already on the device, the download library,
 * and the last known state of each source. Nothing here awaits a network call, which is
 * `home-screen`'s central requirement: the surface "renders complete and immediately, with
 * the same shelves in the same order" whether every source is up or every one is down.
 *
 * The assembly itself lives in [HomeShelves], which is pure and asserted on a plain JVM;
 * the drawing lives in [HomeScreen], which is Material's. This is only the wiring between
 * them, and it is deliberately the only part that knows a source exists.
 */
@Composable
internal fun HomeDestination(host: AppHost) {
    val publications by host.library.publications.collectAsStateWithLifecycle()
    val registry by host.library.registry.collectAsStateWithLifecycle()
    val downloads = host.downloads.value

    // Home is the destination the app opens on, so it is the first screen with a reason to
    // ask for the library. Without this the surface was empty until the reader visited the
    // library once and its own effect ran — which reads exactly like the reading history
    // being lost, and is the opposite of `home-screen`'s "renders complete and
    // immediately". Guarded on the library being empty so that coming back to Home does not
    // restart a walk that has already happened.
    LaunchedEffect(Unit) {
        if (host.library.publications.value.isEmpty()) host.library.restoreFolders()
    }

    // Read straight from the local store rather than through the library's own progress map,
    // which is private to it. A second read of a table of at most a few hundred rows, on the
    // device, is cheaper than widening a view model that six other screens share.
    var records by remember { mutableStateOf<List<ReadingProgress>>(emptyList()) }
    // On resume, not on first composition alone: the comic reader is a composable in this
    // activity and the EPUB reader is an activity of its own, so "the reader closed" reaches
    // this screen two different ways and only one of them recomposes it.
    var resumes by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { resumes++ }
    LaunchedEffect(publications, resumes) {
        records = runCatching { host.dependencies.progress.recent(limit = RECORD_LIMIT) }
            .getOrDefault(emptyList())
    }

    // Matched once per reload rather than per lookup. A reading record is found by identity,
    // which matches on whichever component both sides carry -- a walk over the records for
    // every publication is what the library already does, and doing it once here turns
    // every question the assembly asks into a map lookup.
    val progress: Map<String, ReadingProgress> = remember(publications, records) {
        publications
            .mapNotNull { publication ->
                records.firstOrNull { it.identity.matches(publication.identity) }
                    ?.let { publication.id to it }
            }
            .toMap()
    }

    val onDevice = remember(downloads) { downloads.finished.map { it.id }.toSet() }

    /**
     * Whether a publication can be opened at this instant, asked of the library.
     *
     * **This screen used to answer it itself, and got both of the two mistakes the shared
     * rule was written to prevent.** `isReadableNow` in `:feature:library` says in as many
     * words that it deliberately does not use `SourceConnectionState.canFetch` — every
     * network source is probed when the library appears, so treating "still asking" as
     * "cannot be reached" greys the whole shelf on every launch — and deliberately does not
     * consult the format, because dimming a CB7 as well "would conflate 'your network is
     * down' with 'this file is a CB7'". Home's own copy used `canFetch` **and**
     * `publication.isOpenable`.
     *
     * Measured on an emulator rather than reasoned about: with a picked folder answering,
     * Home labelled four part-read publications "Can't be opened right now" and kept doing
     * so for fifty-two seconds, while the library one tap away drew the same publications
     * undimmed and openable. Two screens, one question, two answers.
     *
     * So Home asks the library now. The lambda stays a lambda because `HomeShelves.assemble`
     * takes one, which is what let a second implementation slip in behind it.
     */
    val isReadableNow: (Publication) -> Boolean = { host.library.isReadableNow(it) }

    // `locations` is part of the library's answer and is not a key here, so the surface is
    // keyed on the registry and on the publication list that a scan replaces. A scan that
    // resolves where a publication lives publishes a new list, which is what re-runs this.
    val surface: HomeSurface = remember(publications, progress, onDevice, registry) {
        HomeShelves.assemble(
            publications = publications,
            progress = { progress[it.id] },
            isReadableNow = isReadableNow,
            nowEpochMillis = System.currentTimeMillis(),
        )
    }

    // `sources`: the first action opens a comic from the device "with nothing to configure
    // first". Everything, rather than a list of comic types -- a provider resolves `.cbz`
    // through `MimeTypeMap`, which has never heard of it, so a filter naming the comic types
    // would grey out every comic on the device.
    val openFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {
        uri: Uri? -> uri?.let { host.library.importFile(it) }
    }

    // The plain secondary. Android hands a picked folder over as a tree `Uri` and grants
    // access to it only for this process — until the app asks for the grant to be
    // persisted, which can only be done here, with the result in hand. That single call is
    // what makes `local-library`'s "reachable after a device restart" true.
    //
    // It used to be a button reading "Connect a library" that carried the reader to the
    // Library destination, where the empty state named four transports at them. One tap
    // that finishes the job, in the same words iOS uses, replaces it.
    val pickFolder = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree(),
    ) { tree: Uri? ->
        if (tree != null) {
            runCatching {
                host.activity.contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            host.library.addFolder(tree)
        }
    }

    HomeScreen(
        surface = surface,
        cover = host.library::cover,
        // A cover leads to the publication's page; Keep reading opens the book. The two
        // are different verbs and `publication-detail` makes the distinction a requirement
        // rather than a habit.
        onOpen = host.openPage,
        onResume = { publication -> resume(host, publication, isReadableNow(publication)) },
        onShowAll = { section -> showAll(host, section) },
        onOpenFile = { openFile.launch(arrayOf("*/*")) },
        onAddFolder = { pickFolder.launch(null) },
    )
}

/**
 * What taking the Keep reading card does.
 *
 * Readable now: straight into the reader at the recorded position, with no intermediate
 * screen, which `home-screen` asks for by name and `publication-detail` repeats from the
 * other side — resuming happens "without this page in between".
 *
 * Not readable now: through [AppHost.browse], the one rule that already decides what an
 * unreachable or refused source leads to. `home-screen` requires the entry to still be
 * offered "with what it needs stated plainly" — and the screen that names the source and
 * offers to try again is exactly that, rather than a tap that does nothing.
 *
 * Every other shelf on this surface is covers, and a cover goes to [AppHost.openPage].
 */
private fun resume(host: AppHost, publication: Publication, isReadableNow: Boolean) {
    if (isReadableNow) {
        host.library.location(publication)?.let { host.open(publication, it) }
        return
    }
    val source = host.library.registry.value.sources.firstOrNull { it.id == publication.sourceId }
    if (source != null) host.browse(source, "")
}

/**
 * Where a shelf's heading leads.
 *
 * `home-screen`: "no shelf silently truncates without offering the rest" — the heading
 * leads to the library "filtered to match the shelf". The filter is set on the library's
 * own query, which is the thing that already persists, so a reader who arrives this way and
 * then narrows further is working on one view rather than on a copy of one.
 *
 * The search term is cleared and everything else the reader set is kept: they chose those
 * filters, and a heading is not a reason to undo them.
 */
private fun showAll(host: AppHost, section: HomeSection) {
    val current = host.library.query.value
    val filtered: LibraryQuery = when (section) {
        HomeSection.KEEP_READING -> current.copy(
            search = "",
            readStates = setOf(ReadState.IN_PROGRESS),
            sort = LibrarySort.LAST_READ,
        )

        // The successors are unread by definition, and a series reads in order, so the
        // library shows them the way a shelf of a series is shelved.
        HomeSection.UP_NEXT -> current.copy(
            search = "",
            readStates = setOf(ReadState.UNREAD),
            sort = LibrarySort.SERIES,
        )

        // No read state: what arrived recently is interesting whether or not it has been
        // opened, and narrowing it to unread would hide the volume the reader added and
        // started the same evening.
        HomeSection.RECENTLY_ADDED -> current.copy(
            search = "",
            readStates = emptySet(),
            sort = LibrarySort.DATE_ADDED,
        )

        HomeSection.FINISHED -> current.copy(
            search = "",
            readStates = setOf(ReadState.FINISHED),
            sort = LibrarySort.LAST_READ,
        )
    }
    host.library.setQuery(filtered)
    host.goToLibrary()
}

/**
 * How many reading records the surface is built from.
 *
 * The same number the library reads, and for the same reason: Keep reading holds twelve and
 * the finished shelf a few more, so a few hundred of the most recent records is far more
 * than any shelf can show and far less than a library's whole history.
 */
private const val RECORD_LIMIT = 500
