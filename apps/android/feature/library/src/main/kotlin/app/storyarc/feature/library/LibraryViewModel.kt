package app.storyarc.feature.library

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.mutableStateMapOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.SafTree
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.FolderSnapshot
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.persistence.ImportedCopy
import app.storyarc.core.persistence.documentNameOf
import app.storyarc.core.persistence.importing
import app.storyarc.core.persistence.imports
import app.storyarc.core.persistence.locationOf
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.model.Source
import java.util.UUID
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
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
    /**
     * Where copies the reader imported live. `local-library` asks for them to be kept in
     * "app-managed storage", and this store already owns exactly that -- see
     * [ImportedCopies].
     */
    private val downloadStore: DownloadStore? = null,
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

    fun probeNetworkSources(credentials: CredentialStore?, pins: CertificatePins) {
        viewModelScope.launch {
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
        val restored = SafTree.persistedTrees(resolver)
        val reachable = restored.filter { SafTree.displayName(resolver, it) != null }
        _unavailableFolders.value = (restored - reachable.toSet()).map { nameOf(it) }
        if (reachable.isEmpty()) return
        _folders.value = reachable
        rescan()
        startWatching()
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
        startWatching()
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
        snapshots.remove(tree.toString())
        rescan()
        startWatching()
    }

    /**
     * Scans every folder, and the managed folder when there are none.
     *
     * One job over all of them rather than one job each: cancelling is then a
     * single action, and the found count is the library's rather than a folder's.
     */
    fun rescan() {
        scanJob?.cancel()
        _publications.value = emptyList()
        _visible.value = emptyList()
        _continueReading.value = emptyList()
        covers.clear()
        locations.clear()
        _scanState.value = LibraryScanState.Scanning(0)

        val trees = _folders.value
        scanJob = viewModelScope.launch {
            withContext(Dispatchers.IO) {
                var found = 0
                var skipped = 0
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
                            is ScanEvent.Found -> append(event.publication, tree)
                            is ScanEvent.Skipped -> Unit
                            is ScanEvent.Finished -> {
                                found += event.found
                                skipped += event.skipped
                            }
                        }
                    }
                }
                _scanState.value = LibraryScanState.Finished(found, skipped)
                // What each folder held at the moment the scan agreed with it. Without this
                // the first reconcile would see every file as new and re-read the whole
                // library to learn nothing.
                for (tree in trees) {
                    snapshots[tree.toString()] =
                        FolderSnapshot.of(LibraryScanner.entries(resolver, tree))
                }
                rebuild()
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
        if (!adopt(publication, sourceOf(tree))) return
        (_scanState.value as? LibraryScanState.Scanning)?.let {
            _scanState.value = LibraryScanState.Scanning(it.found + 1)
        }
        // ponytail: re-arranged in batches during a scan, not per publication --
        // sorting after every one of 10,000 appends is quadratic. The scan's own
        // completion rebuilds the rest, so the only visible effect is that the
        // last few rows arrive together.
        if (_publications.value.size % REBUILD_EVERY == 0) rebuild()
    }

    /**
     * Puts a publication in the library under the source it was reached through, and says
     * whether it was new.
     *
     * Shared by the folder scan and by the imported copies, which find publications two
     * entirely different ways and have to agree about what one row means.
     */
    private fun adopt(publication: Publication, sourceId: UUID?): Boolean {
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
            return false
        }

        publication.identity.normalizedPath?.let { locations[publication.id] = it }
        _publications.update { it + publication.copy(sourceId = sourceId) }
        return true
    }

    // Watched changes

    /**
     * What each watched folder held when it was last looked at, keyed by the tree it came
     * from.
     *
     * In memory rather than on disk. `local-library` asks for a change made while the app was
     * away to be reconciled cheaply, and a launch has nothing to reconcile *against* -- the
     * publications themselves are not cached either, so a snapshot read from disk would
     * describe a library this process has not built yet.
     */
    private val snapshots = mutableMapOf<String, FolderSnapshot>()

    private val watcher = FolderWatcher(resolver)

    /**
     * Watches every folder the reader added.
     *
     * Called whenever the set of folders changes, which is the only thing that invalidates
     * what is being watched.
     */
    private fun startWatching() {
        if (_folders.value.isEmpty()) {
            watcher.stop()
            return
        }
        watcher.watch(_folders.value) { reconcileWatchedFolders() }
    }

    /** Stops watching. The library stays; only the registrations go. */
    fun stopWatching() {
        watcher.stop()
    }

    override fun onCleared() {
        watcher.stop()
        super.onCleared()
    }

    /** Brings every watched folder up to date. */
    fun reconcileWatchedFolders() {
        val trees = _folders.value
        if (trees.isEmpty()) return
        viewModelScope.launch {
            for (tree in trees) reconcile(tree)
        }
    }

    /**
     * Notices what changed in one folder, and re-reads only that.
     *
     * Nothing happens at all when the folder is unchanged, which is the common case: the
     * listing is compared, it matches, and not one archive is opened.
     */
    private suspend fun reconcile(tree: Uri) {
        val listing = withContext(Dispatchers.IO) { LibraryScanner.listing(resolver, tree) }
        val walked = listing.map { it.entry }
        val snapshot = snapshots[tree.toString()] ?: FolderSnapshot()
        // Null means the walk found nothing where something used to be -- an unreadable
        // folder far more often than a reader who deleted every book. Nothing is removed and
        // the snapshot is left alone; see `FolderSnapshot.change`.
        val change = snapshot.change(walked) ?: return
        if (change.isEmpty) return

        val sourceId = sourceOf(tree)
        // A changed file is re-read from scratch rather than patched: its series, its page
        // count and its cover can all have moved, and there is no cheaper honest answer.
        for (path in change.removed + change.changed.map { it.path }) forget(path)

        val byPath = listing.associateBy { it.entry.path }
        for (entry in change.toIndex) {
            val listed = byPath[entry.path] ?: continue
            val publication = withContext(Dispatchers.IO) {
                runCatching { LibraryScanner.index(resolver, tree, listed) }.getOrNull()
            } ?: continue
            adopt(publication, sourceId)
            locations[publication.id] = entry.path
        }

        snapshots[tree.toString()] = snapshot.updated(walked)
        rebuild()
        refreshProgress()
    }

    /**
     * Drops the row for a file that has gone or has been replaced.
     *
     * By path rather than by identity, because the path is the only thing a directory
     * listing knows -- and it is what [locations] is keyed on for exactly this.
     */
    private fun forget(path: String) {
        val gone = locations.filterValues { it == path }.keys.toSet()
        if (gone.isEmpty()) return
        _publications.update { current -> current.filterNot { it.id in gone } }
        locations.keys.removeAll(gone)
    }

    // Imported copies

    /**
     * The last import that did not happen, named so the reader can be told which file.
     *
     * `local-library` forbids a generic failure elsewhere and there is no reason an import
     * should be the exception: a reader who picked the wrong file needs to know it was the
     * file rather than the app.
     */
    private val _importFailure = MutableStateFlow<String?>(null)
    val importFailure: StateFlow<String?> = _importFailure.asStateFlow()

    fun dismissImportFailure() {
        _importFailure.value = null
    }

    /**
     * Copies a publication into app storage and puts it in the library.
     *
     * The copy is indexed the same way a scanned file is, through [PublicationIndexer], so
     * an imported comic carries the same title, series and cover a found one does. Indexing
     * the *copy* rather than the original is what makes the promise true: from here on the
     * library reads only bytes the app owns.
     */
    fun importFile(uri: Uri) {
        val store = downloadStore ?: return
        viewModelScope.launch {
            val copy: ImportedCopy? = withContext(Dispatchers.IO) {
                runCatching { store.importing(resolver, uri, store.library()) }.getOrNull()
            }
            if (copy == null) {
                // Named, not silent. A reader who picked a file StoryArc cannot read has no
                // way to tell that from a broken app unless the app says which it is.
                _importFailure.value = withContext(Dispatchers.IO) {
                    documentNameOf(resolver, uri)
                }
                return@launch
            }
            registerImportedSource()
            indexImport(copy.file)
            rebuild()
        }
    }

    /**
     * Reconciles the library with what has actually been imported.
     *
     * Called on every resume rather than once on launch, because the copies can change while
     * the library is off screen: Settings is where one is deleted, and a library that only
     * read the store at startup would keep offering a book whose bytes are gone.
     */
    fun refreshImports() {
        val store = downloadStore ?: return
        viewModelScope.launch {
            val imports = withContext(Dispatchers.IO) { store.imports(store.library()) }
            val files = imports.map { store.locationOf(it).absolutePath }.toSet()

            // Rows whose copy has been deleted go. The record is the authority here, not a
            // filesystem walk: this store is the app's own, so an empty list means the
            // reader deleted their last import rather than that a folder could not be read.
            _publications.update { current ->
                current.filterNot { publication ->
                    publication.sourceId == ImportedCopies.SOURCE_ID &&
                        locations[publication.id].orEmpty() !in files
                }
            }

            if (imports.isEmpty()) {
                forgetImportedSource()
                rebuild()
                return@launch
            }

            registerImportedSource()
            for (download in imports) {
                val file = store.locationOf(download)
                if (!file.exists() || file.absolutePath in locations.values) continue
                indexImport(file)
            }
            rebuild()
        }
    }

    /** What all the imported copies weigh, for a screen that reports the space used. */
    suspend fun importedBytes(): Long {
        val store = downloadStore ?: return 0
        return withContext(Dispatchers.IO) {
            store.imports(store.library()).sumOf { it.downloadedBytes }
        }
    }

    private suspend fun indexImport(file: File) {
        val publication = withContext(Dispatchers.IO) {
            runCatching { PublicationIndexer.index(file) }.getOrNull()
        } ?: return
        adopt(publication, ImportedCopies.SOURCE_ID)
        // Set again rather than left to `adopt`: the identity of a PDF or an EPUB can carry
        // a content digest instead of a path, and the reader still has to be handed the file.
        locations[publication.id] = file.absolutePath
    }

    /**
     * Puts "On this device" in the registry, if it is not there already.
     *
     * Added the moment there is something in it rather than at launch: `sources` requires
     * the empty state to name the four source types, and a fifth row for a source holding
     * nothing would be a source the reader never added.
     */
    private fun registerImportedSource() {
        if (_registry.value[ImportedCopies.SOURCE_ID] != null) return
        _registry.update {
            it.adding(
                Source(
                    id = ImportedCopies.SOURCE_ID,
                    displayName = getApplication<Application>()
                        .getString(R.string.source_on_this_device),
                    kind = SourceKind.LOCAL_FOLDER,
                    state = SourceConnectionState.Connected,
                    // Not a tree `Uri`, and deliberately something no picked folder can be:
                    // a folder's locator is the `Uri` the picker returned, which always
                    // carries a scheme. Without that, a matching folder would be adopted as
                    // the reader's imports.
                    locator = IMPORTED_LOCATOR,
                ),
            )
        }
        sourceStore?.save(_registry.value)
    }

    /**
     * Takes "On this device" out again when the last copy has been deleted.
     *
     * Discarded rather than tombstoned. A tombstone says the reader removed a source and
     * their progress should outlive it; this source was never added by hand, and holding
     * thirty days of retention open for it would be retention for nothing.
     */
    private fun forgetImportedSource() {
        if (_registry.value[ImportedCopies.SOURCE_ID] == null) return
        _registry.update { it.discarding(ImportedCopies.SOURCE_ID) }
        sourceStore?.save(_registry.value)
    }

    private companion object {
        const val REBUILD_EVERY = 24

        /** What "On this device" points at, which is not a folder anyone picked. */
        const val IMPORTED_LOCATOR = "storyarc/imported"
    }

    fun setQuery(value: LibraryQuery) {
        if (value == _query.value) return
        _query.value = value
        preferences?.save(value)
        rebuild()
    }

    /**
     * Clears every filter, keeping the search and the sort.
     *
     * `library-browsing`: an empty-looking library must say filters are active and
     * offer one action to clear them. This is that action.
     */
    fun clearFilters() {
        setQuery(
            _query.value.copy(
                readStates = emptySet(),
                formats = emptySet(),
                languages = emptySet(),
            ),
        )
    }

    /**
     * Formats actually present, so the filter never offers one that would empty
     * the library.
     */
    fun availableFormats(): List<PublicationFormat> =
        _publications.value.map { it.format }.distinct().sortedBy { it.displayName }

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

    suspend fun cover(publication: Publication, maxPixelSize: Int): Bitmap? {
        covers[publication.id]?.let { return it }
        val path = locations[publication.id] ?: return null
        val bitmap = withContext(Dispatchers.IO) {
            runCatching {
                PublicationAccess.anyCover(resolver, publication, path, maxPixelSize)
            }.getOrNull()
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
