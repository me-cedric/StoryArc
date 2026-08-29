package app.storyarc.feature.library

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.mutableStateMapOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.CoverCache
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.SafTree
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.model.Source
import java.util.UUID
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.LibraryCache
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceProbe
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.Shelves
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File

sealed interface LibraryScanState {
    data object Idle : LibraryScanState

    data class Scanning(val found: Int) : LibraryScanState

    data class Finished(val found: Int, val skipped: Int) : LibraryScanState
}

class LibraryViewModel(
    application: Application,
    private val progressStore: ProgressStore? = null,
    private val preferences: LibraryPreferences? = null,
    private val sourceStore: SourceStore? = null,
    private val shelvesStore: ShelvesStore? = null,
) : AndroidViewModel(application) {

    /**
     * The configured sources, in the reader's own order.
     *
     * `sources` requires a registry, and until now the only thing that existed was the
     * value type. A folder is a source: the library's source list was handed an empty list,
     * so it never drew a row for the folder a reader had picked.
     */
    private val _registry = MutableStateFlow(sourceStore?.registry() ?: SourceRegistry())

    private val _serverLists = MutableStateFlow<List<ServerList>>(emptyList())

    /** The reading lists every known Kavita server holds, once they have been asked. */
    val serverLists: StateFlow<List<ServerList>> = _serverLists.asStateFlow()
    val registry: StateFlow<SourceRegistry> = _registry.asStateFlow()

    private val _shelves = MutableStateFlow(shelvesStore?.shelves() ?: Shelves())

    /** The reader's collections and reading lists. */
    val shelves: StateFlow<Shelves> = _shelves.asStateFlow()

    private val _publications = MutableStateFlow<List<Publication>>(emptyList())
    val publications: StateFlow<List<Publication>> = _publications.asStateFlow()

    private val _scanState = MutableStateFlow<LibraryScanState>(LibraryScanState.Idle)
    val scanState: StateFlow<LibraryScanState> = _scanState.asStateFlow()

    /** What the user is looking at. Setting it re-arranges the shelf. */
    private val _query = MutableStateFlow(preferences?.query() ?: LibraryQuery())
    val query: StateFlow<LibraryQuery> = _query.asStateFlow()

    private val _recentSearches =
        MutableStateFlow(preferences?.recentSearches() ?: RecentSearches())

    /** What the reader searched for lately, offered when the field opens. */
    val recentSearches: StateFlow<RecentSearches> = _recentSearches.asStateFlow()

    /**
     * Grid or list. `library-browsing` requires both, and requires the choice to
     * persist.
     */
    private val _layout = MutableStateFlow(preferences?.layout() ?: LibraryLayout.GRID)
    val layout: StateFlow<LibraryLayout> = _layout.asStateFlow()

    fun setLayout(value: LibraryLayout) {
        if (value == _layout.value) return
        _layout.value = value
        preferences?.save(value)
    }

    /**
     * The publications on screen: filtered, ranked and sorted.
     *
     * Its own flow rather than a derived one. `library-browsing` requires a
     * library of 10,000 to stay usable, and recomputing on every recomposition
     * would re-sort all of them each time.
     */
    private val _visible = MutableStateFlow<List<Publication>>(emptyList())
    val visible: StateFlow<List<Publication>> = _visible.asStateFlow()

    /**
     * In-progress publications, most recently read first. Empty means the row is
     * not drawn at all, which is what `library-browsing` asks for.
     */
    private val _continueReading = MutableStateFlow<List<Publication>>(emptyList())
    val continueReading: StateFlow<List<Publication>> = _continueReading.asStateFlow()

    /** Folders the user picked, in the order they picked them. */
    private val _folders = MutableStateFlow<List<Uri>>(emptyList())
    val folders: StateFlow<List<Uri>> = _folders.asStateFlow()

    /**
     * Folders that were remembered and can no longer be reached.
     *
     * `local-library` requires naming the folder and offering a single action to
     * re-pick it, so the names are kept rather than the count.
     */
    private val _unavailableFolders = MutableStateFlow<List<String>>(emptyList())
    val unavailableFolders: StateFlow<List<String>> = _unavailableFolders.asStateFlow()

    private val covers = mutableMapOf<String, Bitmap>()
    private val progress = mutableStateMapOf<String, ReadingProgress>()

    /**
     * Where each publication came from, as the string its identity carries: a
     * filesystem path, or a document `Uri` from a picked folder.
     */
    private val locations = mutableMapOf<String, String>()
    private var scanJob: Job? = null

    /**
     * One progress load at a time.
     *
     * A scan finishing and the screen appearing both ask for progress, and the two
     * used to race: whichever finished last won, and the loser could be the one
     * that read the store before the scan had produced any publications to match
     * against. Cancelling the earlier load makes the most recent request the one
     * that decides.
     */
    private var progressJob: Job? = null

    private val resolver get() = getApplication<Application>().contentResolver

    /**
     * The app's own folder on external storage.
     *
     * Not what a user's library lives in — that is a folder they pick. This is
     * where a file shared to StoryArc lands, and it is what the emulator and the
     * instrumented tests scan without a picker.
     */
    val managedFolder: File
        get() = getApplication<Application>().getExternalFilesDir(null)
            ?: getApplication<Application>().filesDir

    /**
     * Re-opens the folders from a previous launch and scans them.
     *
     * Called once, when the library first appears. The permissions themselves come
     * back from the system, so this only has to decide which of them still point at
     * something readable.
     */
    /**
     * Asks every network source whether it is there, and records the answer.
     *
     * On appearance rather than on a timer: a state older than the last time the library was
     * on screen is a claim about the past, and polling for one would be guessing.
     */
    /**
     * Marks a publication read or unread, and tells the server it came from.
     *
     * `reading-progress` allows a reader to mark a publication read by hand rather than by
     * turning every page, and `kavita-server` requires that state to reach the server so its
     * own UI agrees. Both halves happen here, because a mark that only landed locally would
     * disagree with the shelf the reader is looking at on another device.
     */
    fun mark(
        publication: Publication,
        isRead: Boolean,
        kavita: KavitaProgressStore?,
        credentials: CredentialStore?,
    ) {
        viewModelScope.launch {
            progressStore?.mark(publication.identity, isRead)
            refreshProgress()

            val origin = kavita?.origin(publication.id) ?: return@launch
            KavitaSync.mark(
                kavita,
                _registry.value.sources
                    .firstOrNull { it.id.toString() == origin.sourceId }
                    ?.let { KavitaPage.of(it, credentials)?.address },
                origin,
                isRead,
            )
        }
    }

    /**
     * Forgets a publication's position, so the next open starts at page one.
     *
     * `reading-progress`: "a 'Start from the beginning' action is available ... and it
     * clears progress only after confirmation". The confirmation is the caller's; this is
     * what it confirms.
     *
     * Forgetting rather than rewinding: the record *is* the position, and a record set back
     * to page one is indistinguishable from one that was never read except for the finished
     * flag, which the reader has just said they do not want either.
     */
    fun restart(publication: Publication) {
        viewModelScope.launch {
            progressStore?.forget(publication.identity)
            refreshProgress()
        }
    }

    /**
     * Keeps asking, while any source is still away.
     *
     * `sources` asks for more than one probe: an unreachable source is retried "with
     * exponential backoff starting at 5 seconds and capping at 5 minutes", and one that
     * comes back is reconnected "without user action". A single probe on appearance
     * satisfies neither — a reader whose Wi-Fi returns while they are looking at the
     * library would watch it say "Connecting…" until they left the screen and came back.
     *
     * The schedule is [SourceProbe.delayAfter], which is tested without a network. This is
     * only the loop, and it holds a job rather than launching a second one, so a reader
     * leaving and returning does not end up with two.
     *
     * iOS runs the same loop from its `task` modifier, where cancellation is the view's.
     */
    private var retryJob: Job? = null

    fun retryUnreachableSources(credentials: CredentialStore?, pins: CertificatePins) {
        retryJob?.cancel()
        retryJob = viewModelScope.launch {
            var failures = 0
            while (isActive) {
                val away = _registry.value.sources.any { it.state is SourceConnectionState.Unreachable }
                if (!away) return@launch
                failures += 1
                delay(SourceProbe.delayAfter(failures))
                probeAndWait(credentials, pins)
            }
        }
    }

    /** Stops the retry loop. Called when the library goes away and nobody is looking. */
    fun stopRetrying() {
        retryJob?.cancel()
        retryJob = null
    }

    fun probeNetworkSources(credentials: CredentialStore?, pins: CertificatePins) {
        viewModelScope.launch { probeAndWait(credentials, pins) }
    }

    private suspend fun probeAndWait(credentials: CredentialStore?, pins: CertificatePins) {
        run {
            val reason = getApplication<Application>()
                .getString(R.string.source_state_unauthorized)
            for (source in _registry.value.sources.filter(SourceHealth::canProbe)) {
                val state = SourceHealth.probe(
                    source,
                    credentials,
                    pins,
                    System.currentTimeMillis(),
                    reason,
                )
                _registry.update { it.marking(source.id, state) }
            }
            // Asked at the same moment, because it is the same question -- what does this
            // server have -- and the add-to sheet cannot fetch it for itself without
            // opening a connection every time a reader long-presses a cover.
            _serverLists.value = _registry.value.sources.flatMap { source ->
                val page = KavitaPage.of(source, credentials) ?: return@flatMap emptyList()
                runCatching { KavitaClient(page.address).readingLists() }
                    .getOrDefault(emptyList())
                    .map { ServerList(page, it.id, it.title) }
            }
        }
    }

    /**
     * Adds a publication to one of a server's reading lists.
     *
     * Returns false when the publication did not come from that server. `kavita-server`
     * requires the app to explain that "a server list can only contain that server's
     * publications" rather than silently doing nothing or silently doing the wrong thing.
     */
    suspend fun addToServerList(
        publication: Publication,
        list: ServerList,
        kavita: KavitaProgressStore?,
        credentials: CredentialStore?,
    ): Boolean {
        val origin = kavita?.origin(publication.id) ?: return false
        if (origin.sourceId != list.server.id) return false

        KavitaSync.append(
            kavita,
            _registry.value.sources
                .firstOrNull { it.id.toString() == origin.sourceId }
                ?.let { KavitaPage.of(it, credentials)?.address },
            origin,
            list.id,
        )
        return true
    }

    fun restoreFolders() {
        if (_folders.value.isNotEmpty()) return
        // Before anything is walked, and before any early return below. `sources` asks for
        // the cached catalogue "within 500 ms of the library view appearing", and the walk
        // that follows corrects it in place.
        restoreCachedLibrary()

        val restored = SafTree.persistedTrees(resolver)
        val reachable = restored.filter { SafTree.displayName(resolver, it) != null }
        _unavailableFolders.value = (restored - reachable.toSet()).map { nameOf(it) }
        _folders.value = reachable
        // Even with no folder to restore. `rescan` walks the managed folder when there are
        // no trees — which is where a file shared to StoryArc lands, and what the emulator
        // and the instrumented tests read. Returning early here meant nothing was scanned
        // at launch at all, and a comic dropped into the app's own folder stayed invisible
        // until someone pressed refresh.
        rescan()
    }

    /**
     * Adds a picked folder.
     *
     * The caller takes the persistable permission before calling — it belongs to
     * the `Intent` result and cannot be recovered afterwards.
     */
    fun addFolder(tree: Uri) {
        if (tree in _folders.value) return
        _folders.update { it + tree }
        _unavailableFolders.value = emptyList()
        register(tree)
        rescan()
    }

    /**
     * Records a folder as a source, if it is not one already.
     *
     * Matched on the tree's last path segment, which is what a reader recognises and what
     * the persisted permission comes back as. A folder picked twice is one source, and the
     * reader's own name for it survives — `sources` requires a rename to stick, so
     * re-adding must not overwrite one.
     */
    private fun register(tree: Uri) {
        val name = tree.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: tree.toString()
        val locator = tree.toString()
        // Matched on where the folder *is*, not on what it is called. A reader who renames a
        // source keeps its name; matching by name would fail to recognise it on the next
        // launch and add the same folder a second time.
        val existing = _registry.value.sources.firstOrNull {
            it.kind == SourceKind.LOCAL_FOLDER && it.locator == locator
        }
        _registry.update {
            when {
                // Connected, not connecting. State is never persisted, so every source
                // loads as connecting and something has to answer. For a folder the answer
                // is immediate: there is nothing to probe.
                existing == null -> it.adding(
                    Source(
                        displayName = name,
                        kind = SourceKind.LOCAL_FOLDER,
                        state = SourceConnectionState.Connected,
                        locator = locator,
                    ),
                )
                existing.state != SourceConnectionState.Connected ->
                    it.marking(existing.id, SourceConnectionState.Connected)
                else -> return
            }
        }
        sourceStore?.save(_registry.value)
    }

    /**
     * Renames a source.
     *
     * The identifier does not move, so everything referring to the source follows — which is
     * what `sources` means by a name appearing "everywhere the source is referenced". The
     * folder itself keeps its own name: a reader who calls a folder "Comics" has not asked
     * to rename the directory.
     */
    /**
     * Adds a source the reader configured elsewhere, such as a catalogue.
     *
     * Distinct from the folder path, which adopts a folder the app already found. A
     * catalogue arrives already confirmed -- it answered, and it told us its name -- so
     * there is nothing to match and nothing to probe.
     */
    fun addSource(source: Source) {
        if (_registry.value[source.id] != null) return
        _registry.update { it.adding(source) }
        sourceStore?.save(_registry.value)
    }

    fun renameSource(source: Source, name: String) {
        _registry.update { it.renaming(source.id, name) }
        sourceStore?.save(_registry.value)
    }

    /**
     * Moves a source one place, which decides precedence rather than merely display order.
     *
     * `sources`: the order "persists across launches", and "the library's combined view
     * lists titles from higher sources first when two sources hold the same publication".
     * The second clause needs no code here — the scan walks the registry in order and the
     * first find of an identity wins — but it is why this writes through immediately.
     *
     * One place at a time, because that is what the two buttons on the screen offer. The
     * arithmetic that turns "one place later" into the index a drag would have reported
     * lives in `SourceRegistry`, where a test can reach it without a screen.
     */
    fun reorderSource(source: Source, later: Boolean) {
        _registry.update { it.moving(source.id, later) }
        sourceStore?.save(_registry.value)
    }

    /**
     * Forgets a folder's source, and remembers that it was forgotten.
     *
     * The tombstone is what keeps reading progress for thirty days, per `sources`. It is
     * left for the registry to collect rather than deleted here.
     */
    private fun unregister(tree: Uri) {
        val source = _registry.value.sources.firstOrNull {
            it.kind == SourceKind.LOCAL_FOLDER && it.locator == tree.toString()
        } ?: return
        _registry.update { it.removing(source.id, System.currentTimeMillis()) }
        sourceStore?.save(_registry.value)
    }

    /**
     * Removes a source and the folder behind it.
     *
     * Nothing could do this before: `sources` requires removal and no UI reached
     * [removeFolder], so a reader who picked the wrong folder was stuck with it.
     *
     * The permission goes back, the registry keeps a tombstone so reading progress survives
     * the thirty days the requirement promises, and files on disk are never touched — this
     * removes a *library*, not a reader's comics.
     */
    fun removeSource(source: Source) {
        val tree = _folders.value.firstOrNull { it.toString() == source.locator } ?: return
        removeFolder(tree)
    }

    /** Removes a folder and gives its permission back. */
    fun removeFolder(tree: Uri) {
        _folders.update { it - tree }
        unregister(tree)
        runCatching {
            resolver.releasePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        rescan()
    }

    /**
     * Scans every folder, and the managed folder when there are none.
     *
     * One job over all of them rather than one job each: cancelling is then a
     * single action, and the found count is the library's rather than a folder's.
     */
    /**
     * Walks the folders again, without emptying the shelf first.
     *
     * `sources` asks a refresh to update "the view incrementally rather than clearing it
     * and re-populating". This used to do the opposite: every pull-to-refresh blanked the
     * library, threw away every decoded cover, and rebuilt the lot — so the reader watched
     * their shelf disappear and come back, and the covers were decoded twice for nothing.
     * iOS has always appended; this is Android catching up.
     *
     * What the walk *does* remove is a publication it no longer finds, which is the
     * requirement's other half: "the publication is removed from the library view and its
     * reading progress is retained". Retaining the progress needs no code — it lives in
     * `ProgressStore`, keyed by identity, and nothing here touches it. A file that comes
     * back finds its position waiting.
     */
    fun rescan() {
        scanJob?.cancel()
        restoreCachedLibrary()
        _scanState.value = LibraryScanState.Scanning(_publications.value.size)

        val trees = _folders.value
        scanJob = viewModelScope.launch {
            withContext(Dispatchers.IO) {
                var found = 0
                var skipped = 0
                // What this walk actually saw, so what it did not see can go afterwards.
                val seen = mutableSetOf<String>()
                // Each walk carries the tree it came from, so a publication can be
                // attributed to the source it was reached through. The managed folder is
                // not a source, so its walk carries null.
                val walks: List<Pair<Uri?, Flow<ScanEvent>>> =
                    if (trees.isEmpty()) {
                        listOf(null to LibraryScanner.scan(managedFolder))
                    } else {
                        trees.map { it to LibraryScanner.scan(resolver, it) }
                    }
                for ((tree, walk) in walks) {
                    walk.collect { event ->
                        when (event) {
                            is ScanEvent.Found -> {
                                seen += event.publication.id
                                append(event.publication, tree)
                            }
                            is ScanEvent.Skipped -> Unit
                            is ScanEvent.Finished -> {
                                found += event.found
                                skipped += event.skipped
                            }
                        }
                    }
                }
                // Anything the walk did not meet is gone from the folders it walked.
                // Only ever a removal of rows, never a clear: a reader watching the screen
                // sees the one book they deleted leave, not the whole shelf blink.
                // Only when the walk actually saw something. A walk that found nothing at
                // all is far more likely to be a folder it could not read — a permission
                // dropped, a share offline, a card pulled — than a reader who deleted every
                // book they own. `sources` promises cached content "remains browsable" when
                // a source is unreachable, and emptying the shelf on a failed walk is
                // exactly the opposite. A library genuinely emptied is reconciled by the
                // next walk that finds anything.
                val vanished = if (seen.isEmpty()) {
                    emptyList()
                } else {
                    _publications.value.filterNot { it.id in seen }.map { it.id }
                }
                if (vanished.isNotEmpty()) {
                    _publications.update { list -> list.filterNot { it.id in vanished } }
                    vanished.forEach { covers.remove(it); locations.remove(it) }
                }
                _scanState.value = LibraryScanState.Finished(found, skipped)
                rebuild()
                cacheLibrary()
            }
            // After the walk, not before it. Recorded positions are matched against
            // the publications the scan produced, so refreshing while the list is
            // still empty matches nothing and every cover opens without its bar.
            refreshProgress()
        }
    }

    /**
     * How many publications a source holds.
     *
     * `sources` asks a source's detail screen for its "cached item count". Counted from
     * what the library actually found rather than remembered separately: two numbers that
     * can disagree is how a screen ends up claiming a source has titles it cannot open.
     */
    fun itemCount(sourceId: UUID): Int = _publications.value.count { it.sourceId == sourceId }

    /**
     * The source a tree belongs to, if it is registered as one.
     *
     * Matched on the tree's last path segment, the same key [register] uses. The app's own
     * managed folder is not a source, so a publication found there is unattributed — the
     * honest answer rather than pretending it belongs to a library the reader picked.
     */
    private fun sourceOf(tree: Uri?): UUID? {
        val locator = tree?.toString() ?: return null
        return _registry.value.sources
            .firstOrNull { it.kind == SourceKind.LOCAL_FOLDER && it.locator == locator }
            ?.id
    }

    /** Scans one local folder. The instrumented tests and the emulator use this. */
    fun scan(folder: File = managedFolder) {
        scanJob?.cancel()
        _publications.value = emptyList()
        _visible.value = emptyList()
        _continueReading.value = emptyList()
        covers.clear()
        locations.clear()
        _scanState.value = LibraryScanState.Scanning(0)

        scanJob = viewModelScope.launch {
            withContext(Dispatchers.IO) {
                LibraryScanner.scan(folder).collect { event ->
                    when (event) {
                        is ScanEvent.Found -> append(event.publication)
                        is ScanEvent.Skipped -> Unit
                        is ScanEvent.Finished -> {
                            _scanState.value = LibraryScanState.Finished(event.found, event.skipped)
                            rebuild()
                        }
                    }
                }
            }
            refreshProgress()
        }
    }

    fun cancelScan() {
        scanJob?.cancel()
        scanJob = null
        (_scanState.value as? LibraryScanState.Scanning)?.let {
            _scanState.value = LibraryScanState.Finished(it.found, 0)
        }
    }

    private fun append(publication: Publication, tree: Uri? = null) {
        // Attributed here rather than by the indexer, which reads bytes and has no idea a
        // registry exists. `sources` needs this for a source's item count, and
        // `library-browsing` for the order two sources holding one title appear in.
        val sourceId = sourceOf(tree)

        val seen = _publications.value.indexOfFirst { it.identity.matches(publication.identity) }
        if (seen >= 0) {
            // Unless the second find knows something the first did not. The app's own files
            // directory is scanned before any source is restored, so a reader whose library
            // lives there had every publication found unattributed first -- and a source
            // that holds eleven books reported nought. Whichever scan carries a source wins.
            if (_publications.value[seen].sourceId == null && sourceId != null) {
                _publications.update { current ->
                    current.mapIndexed { index, existing ->
                        if (index == seen) existing.copy(sourceId = sourceId) else existing
                    }
                }
            }
            return
        }

        publication.identity.normalizedPath?.let { locations[publication.id] = it }
        _publications.update { it + publication.copy(sourceId = sourceId) }
        (_scanState.value as? LibraryScanState.Scanning)?.let {
            _scanState.value = LibraryScanState.Scanning(it.found + 1)
        }
        // ponytail: re-arranged in batches during a scan, not per publication --
        // sorting after every one of 10,000 appends is quadratic. The scan's own
        // completion rebuilds the rest, so the only visible effect is that the
        // last few rows arrive together.
        if (_publications.value.size % REBUILD_EVERY == 0) rebuild()
    }

    private companion object {
        const val REBUILD_EVERY = 24
    }

    fun setQuery(value: LibraryQuery) {
        if (value == _query.value) return
        _query.value = value
        // A term is filed as it is typed. `library-browsing` has results update per
        // keystroke with no submit action, and a reader who taps a cover never ends
        // the search at all — so there is no later moment to hang the record on.
        // [RecentSearches] folds the keystrokes of one word back into one entry,
        // which is what makes recording each of them safe.
        remember(value.search)
        preferences?.save(value)
        rebuild()
    }

    /** `library-browsing`: the offered queries "can be cleared". */
    fun clearRecentSearches() {
        _recentSearches.value = RecentSearches()
        preferences?.save(_recentSearches.value)
    }

    private fun remember(term: String) {
        val updated = _recentSearches.value.recording(term)
        if (updated == _recentSearches.value) return
        _recentSearches.value = updated
        preferences?.save(updated)
    }

    /**
     * Clears every filter, keeping the search and the sort.
     *
     * `library-browsing`: an empty-looking library must say filters are active and
     * offer one action to clear them. This is that action. Which groups it clears
     * lives on the query itself, so a facet added to the query cannot be forgotten
     * here.
     */
    fun clearFilters() {
        setQuery(_query.value.withoutFilters())
    }

    /**
     * Formats actually present, so the filter never offers one that would empty
     * the library.
     */
    fun availableFormats(): List<PublicationFormat> =
        _publications.value.map { it.format }.distinct().sortedBy { it.displayName }

    /** Languages actually present, as codes. The screen names them for the reader. */
    fun availableLanguages(): List<String> =
        _publications.value.mapNotNull { it.language }.distinct().sorted()

    /** Publishers actually present, as the files spell them. */
    fun availablePublishers(): List<String> =
        _publications.value.mapNotNull { it.publisher }.distinct().sorted()

    /** Genres actually present, gathered from every publication's list. */
    fun availableGenres(): List<String> =
        _publications.value.flatMap { it.genres }.distinct().sorted()

    /** Tags actually present. Kept apart from [availableGenres] because the files do. */
    fun availableTags(): List<String> =
        _publications.value.flatMap { it.tags }.distinct().sorted()

    /**
     * The decades the library spans, newest first.
     *
     * `library-browsing` asks for a year *range*, and [LibraryQuery.years] carries
     * an arbitrary one — which is what the tests assert and what a future control
     * will set. What the menu offers is decades, because a menu cannot ask for two
     * numbers without becoming a form, and a decade is a range a reader picks in one
     * tap. Derived from the years actually present, so the filter never offers a
     * decade the library has nothing in.
     */
    fun availableDecades(): List<Int> =
        _publications.value.mapNotNull { it.year }.map { it - it % 10 }.distinct().sortedDescending()

    /** Recomputes what is on screen from the library and the query. */
    private fun rebuild() {
        val all = _publications.value
        _visible.value = LibraryIndex.arrange(all, _query.value, progress = ::stateOf)
        _continueReading.value = LibraryIndex.continueReading(all, progress = ::stateOf)
    }

    private fun stateOf(publication: Publication) = LibraryIndex.Progress.of(progress[publication.id])

    fun readFraction(publication: Publication): Float? {
        val record = progress[publication.id] ?: return null
        if (record.isFinished) return 1f
        val fraction = record.position.fraction.toFloat()
        return if (fraction > 0f) fraction else null
    }

    fun refreshProgress() {
        val store = progressStore ?: return
        progressJob?.cancel()
        progressJob = viewModelScope.launch {
            val records = runCatching { store.recent(limit = 500) }.getOrDefault(emptyList())
            progress.clear()
            for (publication in _publications.value) {
                records.firstOrNull { it.identity.matches(publication.identity) }
                    ?.let { progress[publication.id] = it }
            }
            rebuild()
        }
    }

    /** Where a publication lives, as a path or a document `Uri`. */
    fun location(publication: Publication): String? = locations[publication.id]

    /** A folder's name, for the picker list and the unreachable notice. */
    fun nameOf(tree: Uri): String =
        SafTree.displayName(resolver, tree)
            ?: tree.lastPathSegment?.substringAfterLast(':')?.substringAfterLast('/')
            ?: tree.toString()

    /**
     * Covers on disk, between the ones in memory and the archives they came from.
     *
     * `sources` asks for a cover to be "stored on disk at display resolution", and the
     * reason is what it skips: without it every launch reopened an archive, inflated an
     * entry and decoded an image, per cover, to draw a grid the reader had already seen.
     */
    private val coverCache by lazy { CoverCache(File(getApplication<Application>().cacheDir, "covers")) }

    /**
     * Last session's shelf, so opening the app does not mean walking every folder before
     * anything appears. `sources` asks for the cached catalogue "within 500 ms of the
     * library view appearing", and a folder walk is not that.
     */
    private val libraryCache by lazy {
        LibraryCache(File(getApplication<Application>().cacheDir, "library.json"))
    }

    private val _cachedAt = MutableStateFlow<Long?>(null)

    /**
     * When the shelf on screen was last confirmed, while it is still the cached one.
     *
     * `sources` asks for "a single unobtrusive indicator" stating that content is cached and
     * when it was last refreshed. Null once a walk has finished, because at that point the
     * shelf is not cached — it is current, and saying otherwise would be the indicator lying
     * quietly in the corner.
     */
    val cachedAt: StateFlow<Long?> = _cachedAt.asStateFlow()

    /**
     * Puts last session's shelf back before anything is walked.
     *
     * What follows is a scan, which appends to this rather than replacing it and removes
     * only what it can prove is gone — so the reader sees their library at once and watches
     * it correct itself, instead of watching it appear.
     */
    private fun restoreCachedLibrary() {
        if (_publications.value.isNotEmpty()) return
        val snapshot = libraryCache.read() ?: return
        _publications.value = snapshot.publications
        locations.putAll(snapshot.locations)
        _cachedAt.value = snapshot.refreshedAtEpochMillis
        rebuild()
    }

    /**
     * Records the shelf as it now stands, for the next launch.
     *
     * Called when a walk finishes rather than as publications arrive: a snapshot written
     * mid-scan is a half-library, and restoring one would show a shelf missing books for no
     * reason a reader could see.
     */
    private fun cacheLibrary() {
        // Same reason as the reconciliation above: a walk that found nothing must not
        // replace a good snapshot with an empty one, or one unreadable folder costs the
        // reader their whole cached shelf on the next launch too.
        if (_publications.value.isEmpty() && libraryCache.read()?.publications?.isNotEmpty() == true) return
        libraryCache.write(
            LibraryCache.Snapshot(
                refreshedAtEpochMillis = System.currentTimeMillis(),
                publications = _publications.value,
                locations = locations.toMap(),
            ),
        )
        _cachedAt.value = null
    }

    suspend fun cover(publication: Publication, maxPixelSize: Int): Bitmap? {
        covers[publication.id]?.let { return it }

        withContext(Dispatchers.IO) { coverCache.bitmap(publication.id, maxPixelSize) }?.let {
            covers[publication.id] = it
            return it
        }

        val path = locations[publication.id] ?: return null
        val bitmap = withContext(Dispatchers.IO) {
            runCatching {
                PublicationAccess.anyCover(resolver, publication, path, maxPixelSize)
            }.getOrNull()?.also { coverCache.store(it, publication.id, maxPixelSize) }
        } ?: return null
        covers[publication.id] = bitmap
        return bitmap
    }

    // Collections and reading lists

    /**
     * Every publication the reader has finished, for a reading list's progress line.
     *
     * A set rather than a predicate, because a list of forty entries would otherwise ask the
     * progress store forty times while drawing one screen.
     */
    fun finishedPublications(): Set<String> =
        progress.filterValues { it.isFinished }.keys

    fun createCollection(name: String) {
        if (name.isBlank()) return
        _shelves.update { it.adding(PublicationCollection(name = name.trim())) }
        shelvesStore?.save(_shelves.value)
    }

    fun createList(name: String) {
        if (name.isBlank()) return
        _shelves.update { it.adding(ReadingList(name = name.trim())) }
        shelvesStore?.save(_shelves.value)
    }

    fun addToCollection(members: Set<String>, id: UUID) {
        _shelves.update { it.adding(members, id) }
        shelvesStore?.save(_shelves.value)
    }

    fun appendToList(entries: List<String>, id: UUID) {
        _shelves.update { it.appending(entries, id) }
        shelvesStore?.save(_shelves.value)
    }

    fun removeFromList(entry: String, id: UUID) {
        _shelves.update { it.removing(entry, id) }
        shelvesStore?.save(_shelves.value)
    }

    fun moveInList(entry: String, destination: Int, id: UUID) {
        _shelves.update { it.moving(entry, destination, id) }
        shelvesStore?.save(_shelves.value)
    }

    fun deleteCollection(id: UUID) {
        _shelves.update { it.deletingCollection(id) }
        shelvesStore?.save(_shelves.value)
    }

    fun deleteList(id: UUID) {
        _shelves.update { it.deletingList(id) }
        shelvesStore?.save(_shelves.value)
    }

    /**
     * What to offer when a publication is finished.
     *
     * A reading list wins over a series. `collections-and-reading-lists`: when a reader
     * finishes an entry in a list, "the next entry in list order is offered, regardless of
     * series or source" -- a crossover read in publication order is exactly a case where the
     * series' own next issue is the wrong answer.
     *
     * The first list containing it decides, when a publication is in several. Any rule here
     * is arbitrary; this one is at least the reader's own order, since the lists are in the
     * order they made them.
     *
     * Falls back to the series, which is what `comic-reader` asks for and what a reader who
     * keeps no lists will always get.
     */
    fun next(after: Publication): Publication? {
        val known = _publications.value
        for (list in _shelves.value.lists) {
            if (after.id !in list.entries) continue
            val nextId = list.next(after.id) ?: continue
            // An entry whose publication is gone does not stop the flow: the spec says an
            // unavailable entry "does not break the ordering or the next flow".
            known.firstOrNull { it.id == nextId }?.let { return it }
        }
        return LibraryIndex.next(after, known)
    }
}
