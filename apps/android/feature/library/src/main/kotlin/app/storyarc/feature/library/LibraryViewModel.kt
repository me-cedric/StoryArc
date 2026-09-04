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
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.SafTree
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.FolderSnapshot
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Publication
import app.storyarc.core.model.grouped
import app.storyarc.core.model.inScope
import app.storyarc.core.model.nameOf
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
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
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.LibraryCache
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourcePrecedence
import app.storyarc.core.model.SourceProbe
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.Shelves
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ScanJournal
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
    /**
     * What an interrupted scan wrote down. `local-library` requires a scan to be
     * "cancellable and resumable" -- see [ScanJournal] for why those are one promise.
     */
    private val journal: ScanJournal? = null,
    /**
     * What a Kavita server said about the downloads it produced.
     *
     * Read when a download joins the shelf, so the row carries the server's description
     * rather than the file's -- which is what `kavita-server` requires whether or not the
     * server can be reached. Null for a view model built without one, the way every other
     * store here is optional.
     */
    private val cards: KavitaCardStore? = null,
) : AndroidViewModel(application) {

    /**
     * The configured sources, in the reader's own order.
     *
     * `sources` requires a registry, and until now the only thing that existed was the
     * value type. A folder is a source: the library's source list was handed an empty list,
     * so it never drew a row for the folder a reader had picked.
     */
    // Internal rather than private, these three, for the reason iOS's `LibraryModel` gives
    // for the same fields: `private` is file-scoped in Kotlin as in Swift, and the source
    // health half of this class lives in `SourceRetry.kt` because this file is at the length
    // the line cap records for it.
    internal val _registry = MutableStateFlow(sourceStore?.registry() ?: SourceRegistry())

    internal val _serverLists = MutableStateFlow<List<ServerList>>(emptyList())

    /** The reading lists every known Kavita server holds, once they have been asked. */
    val serverLists: StateFlow<List<ServerList>> = _serverLists.asStateFlow()

    internal val _listServers = MutableStateFlow<List<KavitaPage>>(emptyList())

    /**
     * The servers that answered that question: reachable, and able to hold a list.
     *
     * Answered rather than non-empty. A server with no reading lists yet still supports them,
     * and is exactly the one a reader is most likely to want to copy their first list onto;
     * a server that did not answer supports nothing this app can see, and is not offered.
     */
    val listServers: StateFlow<List<KavitaPage>> = _listServers.asStateFlow()
    val registry: StateFlow<SourceRegistry> = _registry.asStateFlow()

    private val _shelves = MutableStateFlow(shelvesStore?.shelves() ?: Shelves())

    /** The reader's collections and reading lists. */
    val shelves: StateFlow<Shelves> = _shelves.asStateFlow()

    private val _publications = MutableStateFlow<List<Publication>>(emptyList())
    val publications: StateFlow<List<Publication>> = _publications.asStateFlow()

    private val _scanState = MutableStateFlow<LibraryScanState>(LibraryScanState.Idle)
    val scanState: StateFlow<LibraryScanState> = _scanState.asStateFlow()

    /** What the library could not open, and whether the reader has been told. */
    private val _skipped = MutableStateFlow(SkippedPublications())
    val skipped: StateFlow<SkippedPublications> = _skipped.asStateFlow()
    /** The reader put the notice away. `library-browsing` keeps the list reachable. */
    fun dismissSkipped() = _skipped.update { it.dismissing() }

    /** What the user is looking at. Setting it re-arranges the shelf. */
    private val _query = MutableStateFlow(
        // Resolved against the registry as it was read back, so a scope naming a source
        // removed in the last session opens the whole library rather than an empty one.
        (preferences?.query() ?: LibraryQuery()).let {
            it.copy(scope = it.scope.resolved(_registry.value))
        },
    )
    val query: StateFlow<LibraryQuery> = _query.asStateFlow()

    private val _recentSearches =
        MutableStateFlow(preferences?.recentSearches() ?: RecentSearches())

    /** What the reader searched for lately, offered when the field opens. */
    val recentSearches: StateFlow<RecentSearches> = _recentSearches.asStateFlow()

    /**
     * What the **search screen** is narrowed to.
     *
     * Held here rather than in `SearchScreen`'s own `rememberSaveable`, which is what carried
     * it and is not what `library-browsing` asks for: the choice "persists until changed", and
     * a launch is not a change. Saved state dies with the process, so a reader who narrowed to
     * what is on the device came back to a search that had quietly widened itself.
     *
     * Its own key beside the shelf's axis, never the same one. `navigation-shell` promises a
     * reader leaving search returns to the destination they were on "with its filters intact",
     * and one shared key would have narrowing a search narrow the shelf they go back to. See
     * [app.storyarc.core.persistence.LibraryPreferences.searchScope].
     */
    private val _searchScope =
        MutableStateFlow(LibraryAvailability.named(preferences?.searchScope()))

    val searchScope: StateFlow<LibraryAvailability> = _searchScope.asStateFlow()

    fun setSearchScope(value: LibraryAvailability) {
        if (value == _searchScope.value) return
        _searchScope.value = value
        preferences?.saveSearchScope(value.name)
    }

    /**
     * Grid or list. `library-browsing` requires both, and requires the choice to
     * persist per scope.
     */
    private val _layout = MutableStateFlow(
        preferences?.layout(_query.value.scope) ?: LibraryLayout.GRID,
    )
    val layout: StateFlow<LibraryLayout> = _layout.asStateFlow()

    fun setLayout(value: LibraryLayout) {
        if (value == _layout.value) return
        _layout.value = value
        preferences?.save(value, _query.value.scope)
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

    /**
     * Search results, grouped by why each one matched. Empty when nothing is being searched
     * for, and the caller draws the flat shelf then.
     */
    private val _matchGroups = MutableStateFlow<List<MatchGroup>>(emptyList())
    val matchGroups: StateFlow<List<MatchGroup>> = _matchGroups.asStateFlow()

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
    /**
     * The walk currently running.
     *
     * Internal rather than private so a test can wait for it, which is what iOS's
     * `LibraryModel.scanTask` is internal for. Polling a state flow for `Finished` would be
     * the same wait with a sleep in it.
     */
    internal var scanJob: Job? = null

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
     * The backoff loop, while one is running.
     *
     * A member because a job is per view model, while the loop that owns it lives in
     * `SourceRetry.kt` — see that file's header for why the source-health half is not here.
     */
    internal var retryJob: Job? = null

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

    /**
     * Re-opens the folders from a previous launch and scans them.
     *
     * Called once, when the library first appears. The permissions themselves come
     * back from the system, so this only has to decide which of them still point at
     * something readable.
     */
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
        // Connection state is never persisted, so a restored folder loads as *connecting*
        // and stays there — nothing probes a folder. [register] is what answers, and it also
        // corrects a name an older build derived. It adds nothing: a persisted tree
        // permission is one a reader picked, so it is already a source.
        reachable.forEach(::register)
        // Even with no folder to restore: the app's own folder is walked on every scan, and
        // it is where a file shared to StoryArc lands.
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
     * Named by the provider, and only then by its document id — [FolderSourceName] says why
     * a folder was appearing as `primary:Audiobooks`. A folder picked twice is one source,
     * and the reader's own name for it survives: `sources` requires a rename to stick, so
     * re-adding must not overwrite one.
     */
    private fun register(tree: Uri) {
        val segment = tree.lastPathSegment
        val locator = tree.toString()
        val name = FolderSourceName.of(SafTree.displayName(resolver, tree), segment, locator)
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
                FolderSourceName.isRawDocumentId(existing.displayName, segment) ->
                    it.renaming(existing.id, name).marking(existing.id, SourceConnectionState.Connected)
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

    /**
     * Puts a re-authorised source back where it stood.
     *
     * `sources` requires "a single action to re-enter credentials" for a source that was
     * refused. The sheet writes the new secret under the reference the registry already
     * holds, so all this has to do is put the row back — and putting it *back* rather than
     * adding it is the point: the position decides which of two sources wins for a title, and
     * the identifier is what the downloads and the reading positions are filed under.
     */
    fun reconnectSource(source: Source) {
        _registry.update { it.replacing(source) }
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
     * Removes a source, its secret, and the folder behind it when it has one.
     *
     * The permission goes back, the registry keeps a tombstone so reading progress survives
     * the thirty days the requirement promises, and files on disk are never touched — this
     * removes a *library*, not a reader's comics.
     *
     * The secret goes first and unconditionally. `sources` requires removal to take "its
     * stored credentials" with it, and until this nothing in the app had ever called
     * [CredentialStore.remove]: the folder lookup below used to be the first statement, with
     * a `?: return` on the end, so removing a Kavita server or an SMB share did nothing at
     * all and its password stayed on the device for a server the reader believed was gone.
     *
     * `credentials` is a parameter rather than something the view model holds, matching
     * [probeNetworkSources]: the store is a handle to the Keystore and this class has no
     * other use for one.
     */
    fun removeSource(source: Source, credentials: CredentialStore?) {
        val removal = SourceRemoval.of(source, _folders.value.map { it.toString() })
        removal.credentialReference?.let { credentials?.remove(it) }

        val tree = removal.folder?.let { named ->
            _folders.value.firstOrNull { it.toString() == named }
        }
        if (tree != null) {
            removeFolder(tree)
            return
        }
        forget(source)
    }

    /**
     * Asks one source, now, and says so while it is asking.
     *
     * `sources`: a source's detail screen "offers actions to test the connection, refresh,
     * clear the cache, remove downloads, and remove the source". Removal already existed;
     * this and the two below did not, on either platform.
     *
     * Marked `Connecting` first. A test whose only visible effect arrives a network timeout
     * later is a button a reader presses twice. A folder is asked of the content resolver
     * rather than of a network: it is either still readable or it is not, which is the
     * distinction [SourceProbe.isRemote] draws.
     *
     * iOS's `LibraryModel.test` answers the same way.
     */
    fun testSource(source: Source, credentials: CredentialStore?, pins: CertificatePins) {
        if (!SourceProbe.isRemote(source.kind)) {
            _registry.update { it.marking(source.id, folderState(source)) }
            return
        }
        viewModelScope.launch {
            _registry.update { it.marking(source.id, SourceConnectionState.Connecting) }
            val reason = getApplication<Application>().getString(R.string.source_state_unauthorized)
            val state = SourceHealth.probe(
                source,
                credentials,
                pins,
                System.currentTimeMillis(),
                reason,
            )
            _registry.update { it.marking(source.id, state) }
        }
    }

    /**
     * Re-fetches what one source holds.
     *
     * The test first, because a refresh of a source that is not answering is a walk that
     * finds nothing — and a walk that finds nothing is deliberately not allowed to empty the
     * shelf. For a folder the walk is the refresh; for a server the probe is, since a
     * server's contents are browsed rather than folded into the shelf.
     */
    fun refreshSource(source: Source, credentials: CredentialStore?, pins: CertificatePins) {
        testSource(source, credentials, pins)
        if (source.kind == SourceKind.LOCAL_FOLDER) rescan()
    }

    /**
     * Drops what is cached for one source, and nothing else.
     *
     * The rows go, the on-disk snapshot is rewritten without them, and the next refresh puts
     * back whatever is still there. Downloads are untouched: `sources` lists clearing the
     * cache and removing downloads as two actions, and a reader on a train who meant the
     * first must not get the second.
     *
     * Cover *files* are not swept one by one. They live in the cache directory keyed by
     * publication, are evicted under storage pressure, and Privacy's "Clear cache" takes the
     * lot — so those bytes are already reachable by something the reader can press.
     */
    fun clearSourceCache(source: Source) {
        val gone = _publications.value.filter { it.sourceId == source.id }.map { it.id }
        if (gone.isEmpty()) return
        _publications.update { list -> list.filterNot { it.id in gone } }
        gone.forEach { covers.remove(it); locations.remove(it) }
        // Written through rather than left for the next scan. [cacheLibrary] refuses to
        // replace a good snapshot with an empty one — that guard is there for a walk that
        // failed, and this is not one, so an emptied library clears the file outright.
        if (_publications.value.isEmpty()) libraryCache.clear() else cacheLibrary()
        _cachedAt.value = null
        rebuild()
    }

    /**
     * Whether a folder source can still be read.
     *
     * The persisted permission is the question. A tree the system no longer grants is a
     * folder the app cannot open, whatever is on the card — and the answer is grey rather
     * than red, because `local-library` names an unavailable folder separately and "offline
     * is a normal state, not an error".
     */
    private fun folderState(source: Source): SourceConnectionState {
        val granted = resolver.persistedUriPermissions.any {
            it.uri.toString() == source.locator && it.isReadPermission
        }
        return if (granted) {
            SourceConnectionState.Connected
        } else {
            SourceConnectionState.Unreachable(System.currentTimeMillis())
        }
    }

    /**
     * Drops a source that has no folder behind it — a catalogue, a Kavita server, a share.
     *
     * The tombstone rather than a discard, for the reason [unregister] gives: `sources`
     * keeps reading progress for thirty days so re-adding the same server restores where the
     * reader stopped. The publications it contributed go with it and the rest of the shelf
     * stays.
     */
    private fun forget(source: Source) {
        _registry.update { it.removing(source.id, System.currentTimeMillis()) }
        sourceStore?.save(_registry.value)
        _publications.update { list -> list.filterNot { it.sourceId == source.id } }
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
     *
     * Every folder, and the managed folder when there are none — under one job rather than
     * one job each, so cancelling is a single action and the found count is the library's
     * rather than a folder's.
     */
    fun rescan() {
        scanJob?.cancel()
        restoreCachedLibrary()
        _scanState.value = LibraryScanState.Scanning(_publications.value.size)

        val trees = _folders.value
        // Put back before the walk starts, so a reader who left mid-scan comes back to the
        // library they had rather than to an empty grid filling up again.
        val resumed = trees.associate { tree ->
            tree.toString() to journal?.indexed(tree.toString()).orEmpty()
        }
        for ((tree, publications) in resumed) {
            val sourceId = sourceOf(Uri.parse(tree))
            for (publication in publications) {
                adopt(publication, sourceId)
                publication.identity.normalizedPath?.let { locations[publication.id] = it }
            }
        }
        if (_publications.value.isNotEmpty()) {
            _scanState.value = LibraryScanState.Scanning(_publications.value.size)
            rebuild()
        }

        scanJob = viewModelScope.launch {
            withContext(Dispatchers.IO) {
                var found = _publications.value.size
                // The pairs, not a tally -- see [SkippedPublications].
                val refusals = mutableListOf<SkippedPublications.Entry>()
                // What each walk actually saw, so what it did not see can go afterwards --
                // per source, never pooled. See [ScanReconciliation].
                val seenBySource = mutableMapOf<UUID?, MutableSet<String>>()
                // And which of them could not account for themselves. A walk that met a
                // directory it could not list has not proved anything absent -- see
                // [ScanReconciliation] and [cacheLibrary], which are the two decisions that
                // used to treat "found nothing" and "could see nothing" as one answer.
                val partial = mutableSetOf<UUID?>()
                // Each walk carries the tree it came from, so a publication can be
                // attributed to the source it was reached through. The managed folder is
                // not a source, so its walk carries null -- and it is walked on every scan,
                // never instead of the picked trees. See [ScanTargets].
                val walks: List<Pair<Uri?, Flow<ScanEvent>>> =
                    ScanTargets.of(trees.map { it.toString() }).map { target ->
                        // The scope this walk answers for, resolved once so the reporter
                        // below closes over it rather than over the loop variable.
                        val scope = sourceOf(target?.let(Uri::parse))
                        val unreadable: (String) -> Unit = { partial += scope }
                        if (target == null) {
                            return@map null to
                                LibraryScanner.scan(managedFolder, onUnreadableFolder = unreadable)
                        }
                        val tree = Uri.parse(target)
                        // Matched on the path, which is what a directory walk knows. A
                        // publication whose identity is a content digest is still filed
                        // under the document it came out of.
                        val done = resumed[target]
                            .orEmpty()
                            .mapNotNull { it.identity.normalizedPath }
                            .toSet()
                        tree to LibraryScanner.scan(resolver, tree, done, unreadable)
                    }
                for ((tree, walk) in walks) {
                    scanningFolder = tree?.toString()
                    scanned = resumed[tree?.toString()].orEmpty().toMutableList()
                    // Present and empty before the walk starts: a scope that was walked and
                    // found nothing has to be distinguishable from one nothing walked.
                    val seen = seenBySource.getOrPut(sourceOf(tree)) { mutableSetOf() }
                    walk.collect { event ->
                        when (event) {
                            is ScanEvent.Found -> {
                                seen += event.publication.id
                                append(event.publication, tree)
                            }
                            is ScanEvent.Skipped -> refusals += event.asRefusal()
                            is ScanEvent.Finished -> {
                                found += event.found
                                // Nothing left to resume. Cleared rather than kept: this is
                                // a journal, not the metadata cache `sources` asks for, and
                                // a journal that outlived its scan would be a stale library
                                // nobody decided to keep.
                                tree?.let { journal?.clear(it.toString()) }
                            }
                        }
                    }
                }
                // Anything a walk did not meet is gone from the folder that walk covered.
                // Only ever a removal of rows, never a clear: a reader watching the screen
                // sees the one book they deleted leave, not the whole shelf blink. And only
                // from a source whose own walk saw something — [ScanReconciliation] carries
                // the argument, and why asking it of the scan as a whole stopped being safe.
                val vanished = ScanReconciliation.vanished(
                    seenBySource,
                    _publications.value.map { it.id to it.sourceId },
                    partial,
                )
                if (vanished.isNotEmpty()) {
                    _publications.update { list -> list.filterNot { it.id in vanished } }
                    vanished.forEach { covers.remove(it); locations.remove(it) }
                }
                scanningFolder = null
                scanned = mutableListOf()
                _scanState.value = LibraryScanState.Finished(found, refusals.size)
                // Once, after every tree -- settling replaces the list, it does not add.
                _skipped.value = _skipped.value.settling(refusals)
                // What each folder held at the moment the scan agreed with it. Without this
                // the first reconcile would see every file as new and re-read the whole
                // library to learn nothing.
                for (tree in trees) {
                    snapshots[tree.toString()] =
                        FolderSnapshot.of(LibraryScanner.entries(resolver, tree))
                }
                rebuild()
                cacheLibrary(partial.isNotEmpty())
            }
            // After the walk, not before it. Recorded positions are matched against
            // the publications the scan produced, so refreshing while the list is
            // still empty matches nothing and every cover opens without its bar.
            refreshProgress()
        }
    }

    /**
     * Brings finished downloads onto the shelf, each attributed to its source.
     *
     * `library-browsing`'s first requirement is one library "spanning every source", and a
     * download is how a publication from a server comes to be on this device. Until this
     * existed the shelf held what a folder scan found and nothing else: a reader who had
     * downloaded forty chapters from Kavita saw none of them in their library, and could
     * only reach them by browsing back to the server they came from -- which is the opposite
     * of taking a library with you, and made the source selector a list of sources with
     * nothing behind them.
     *
     * The tree is walked rather than each record's path being reconstructed. The record says
     * what a download is called and the writers have not always agreed on the file's name;
     * they have always agreed on the *directory*, which is what [DownloadStore.download]
     * matches on.
     *
     * Only finished downloads. A running one is a partial file, and indexing a truncated
     * archive produces either an error or, worse, a publication with three of its pages.
     */
    fun adoptDownloads() {
        val store = downloadStore ?: return
        viewModelScope.launch {
            val downloads = store.library()
            if (downloads.finished.isEmpty()) return@launch

            var added = false
            withContext(Dispatchers.IO) {
                LibraryScanner.scan(store.directory).collect { event ->
                    val publication = (event as? ScanEvent.Found)?.publication ?: return@collect
                    val path = publication.identity.normalizedPath ?: return@collect
                    val record = store.download(File(path), downloads) ?: return@collect
                    if (!record.state.isFinished) return@collect
                    // What the server said wins over what the file says. `kavita-server` is
                    // explicit: the server is the curated source, and a downloaded Kavita
                    // title read with the server unreachable shows "the cached server
                    // metadata, not the file's embedded metadata". The card is the cache,
                    // written when the chapter was kept, and this is the one place every
                    // kept download passes through on its way to the shelf.
                    val described = cards?.card(publication.id)?.appliedTo(publication)
                        ?: publication
                    if (adopt(described, record.sourceId, path)) added = true
                }
            }
            if (!added) return@launch
            rebuild()
            // Their reading positions too. A chapter downloaded and then read has a position
            // on this device like any other, and the bar under its cover is how a reader sees
            // that the library and the reader are talking about the same book.
            refreshProgress()
        }
    }

    /**
     * Puts one downloaded publication on the shelf.
     *
     * Returns whether the shelf actually changed, so a walk that found nothing new does not
     * trigger a re-sort of the whole library.
     *
     * A publication already there is not added twice: identity decides, not the path, so a
     * comic that lives in a picked folder *and* was downloaded is one row (ADR-0006). The
     * existing row gains the attribution when it had none, for the same reason a second
     * folder scan hands one over -- a row that knows where it came from beats one that does
     * not, whichever found it first.
     */
    private fun adopt(publication: Publication, sourceId: UUID?, path: String): Boolean {
        val seen = _publications.value.indexOfFirst { it.identity.matches(publication.identity) }
        if (seen >= 0) {
            if (_publications.value[seen].sourceId == null && sourceId != null) {
                _publications.update { current ->
                    current.mapIndexed { index, existing ->
                        if (index == seen) existing.copy(sourceId = sourceId) else existing
                    }
                }
            }
            return false
        }

        locations[publication.id] = path
        _publications.update { it + publication.copy(sourceId = sourceId) }
        return true
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

    fun cancelScan() {
        scanJob?.cancel()
        scanJob = null
        // Written down rather than lost, which is what makes the next scan of this folder a
        // resumption instead of a repetition.
        scanningFolder?.let { journal?.record(scanned, it) }
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
        // Written down on the same beat. A journal flushed per publication would cost a
        // preferences write per file; one every two dozen loses at most that many to a
        // process the system reclaims without warning -- which is the case this exists for,
        // because a killed process runs no cleanup of its own.
        scanned += publication
        val folder = scanningFolder
        if (folder != null && scanned.size % REBUILD_EVERY == 0) journal?.record(scanned, folder)
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
            // Unless this find came through a source the reader put higher. `sources`: the
            // combined view "lists titles from higher sources first when two sources hold the
            // same publication" -- so the registry's order decides which copy the row is, not
            // which scan happened to reach it first. [SourcePrecedence] is where that
            // comparison lives and where it is asserted.
            //
            // The unattributed case falls out of the same rule: the app's own files directory
            // is scanned before any source is restored, so a reader whose library lives there
            // had every publication found with no source at all -- and a source holding eleven
            // books reported nought. Null ranks last, so the source wins.
            val existing = _publications.value[seen]
            if (!SourcePrecedence.prefers(sourceId, existing.sourceId, _registry.value.sources)) {
                return false
            }
            _publications.update { current ->
                current.mapIndexed { index, each ->
                    if (index == seen) each.copy(sourceId = sourceId) else each
                }
            }
            // The file goes with the attribution. A row that says one source and opens the
            // other source's copy is the same bug wearing a different hat.
            publication.identity.normalizedPath?.let { locations[existing.id] = it }
            return false
        }

        publication.identity.normalizedPath?.let { locations[publication.id] = it }
        _publications.update { it + publication.copy(sourceId = sourceId) }
        return true
    }

    /**
     * The folder being walked, and what has been indexed in it so far.
     *
     * Held so an interrupted scan can be written down and picked up. `local-library` requires
     * a scan to be "cancellable and resumable", which are one promise: a reader who stops a
     * scan and starts it again should not wait for the same archives twice.
     */
    private var scanningFolder: String? = null
    private var scanned: MutableList<Publication> = mutableListOf()

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
        val previous = _query.value
        if (value == previous) return
        _query.value = value
        // A term is filed as it is typed. `library-browsing` has results update per
        // keystroke with no submit action, and a reader who taps a cover never ends
        // the search at all — so there is no later moment to hang the record on.
        // [RecentSearches] folds the keystrokes of one word back into one entry,
        // which is what makes recording each of them safe.
        remember(value.search)
        preferences?.save(value)
        // A new scope brings its own layout with it. `library-browsing` keeps the grid or
        // list choice per scope, so switching source has to *read* the layout as well as
        // write it -- otherwise whichever scope was open last would quietly impose its
        // choice on the next one.
        if (value.scope != previous.scope) {
            preferences?.let { _layout.value = it.layout(value.scope) }
        }
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
     * Clears every filter, keeping the search, the sort and the scope.
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
     * Shows every source again.
     *
     * `library-browsing` asks the no-results state to "offer to widen the scope to all
     * sources if the search was scoped", which is a different offer from clearing the
     * filters: the reader who scoped to one server and found nothing usually wants the same
     * words put to the rest of their library, not their filters undone.
     */
    fun widenToAllSources() {
        setQuery(_query.value.copy(scope = LibraryScope.AllSources))
    }

    // `sourceName(publication:)` used to be here, and there is deliberately nothing in its
    // place. It answered "which source is this publication from", which is the question no
    // browse surface is allowed to ask: `library-browsing` requires that nothing on the shelf
    // states a publication's origin, and `publication-detail` gives origin exactly one home --
    // the provenance line on the publication's own page, which reads the registry itself.
    //
    // It had **zero callers** and a doc comment quoting the *superseded* rule, that a
    // publication "shows its source only when more than one source is configured". iOS deleted
    // its mirror for the same reason and left the same note at `LibraryLookups.swift`; this one
    // outlived it by a wave because nothing fails when a leak is merely available. A public
    // lookup that answers a forbidden question is an invitation to put the leak back.

    /** Recomputes what is on screen from the library and the query. */
    private fun rebuild() {
        val all = _publications.value
        _visible.value = LibraryIndex.arrange(all, _query.value, progress = ::stateOf)
        _matchGroups.value = LibraryIndex.grouped(all, _query.value, progress = ::stateOf)
        // Narrowed to the scope, not to the whole query: the row is what the reader was in
        // the middle of, and a filter on format has nothing to say about that.
        _continueReading.value = LibraryIndex.continueReading(
            LibraryIndex.inScope(all, _query.value.scope),
            progress = ::stateOf,
        )
    }

    internal fun stateOf(publication: Publication) = LibraryIndex.Progress.of(progress[publication.id])

    /**
     * The local reading record for a publication, or null when it has never been opened.
     *
     * The record itself rather than [stateOf]'s summary, because [SearchSuggestions] needs the
     * position to say how many pages are left — the same question `HomeShelves.pagesRemaining`
     * answers, and it takes the record. Home reads the store a second time instead, because it
     * lives in `:app` and this map is private here. A snapshot-map read, so a composition that
     * asks recomposes when progress reloads.
     */
    internal fun recordOf(publication: Publication): ReadingProgress? = progress[publication.id]

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

    /**
     * Whether this publication carries the on-device mark.
     *
     * The rule is [isKeptOnDevice]; this is the shelf asking it. Here rather than in the cell
     * because the cell has neither the location table nor the download store, and because a
     * question asked once per visible cover on every redraw has to be a map lookup and a
     * string comparison rather than a read of a store.
     */
    fun isOnDevice(publication: Publication): Boolean =
        isKeptOnDevice(locations[publication.id], downloadStore?.directory)

    /**
     * Whether this publication can be opened at this instant.
     *
     * The rule is [isReadableNow]; this is the shelf asking it. It decides an opacity and
     * never a filter — see the rule for why the difference is the whole requirement.
     */
    fun isReadableNow(publication: Publication): Boolean =
        isReadableNow(publication, locations[publication.id], _registry.value)

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
    internal fun restoreCachedLibrary() {
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
    private fun cacheLibrary(partial: Boolean = false) {
        // **The honest limit this change closes.** The notice said "cached, refreshed at X"
        // and left the moment a walk finished — including a walk that saw nothing because it
        // could see nothing, which is when a reader most needs to be told the shelf is last
        // session's. `sources` asks the indicator to say the content is cached and when it
        // was last refreshed; a walk that could not list a directory has refreshed nothing,
        // and writing `now` into the snapshot would put that lie on disk for the next launch
        // as well.
        if (partial) return
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

    /**
     * The app's own download store, for keeping a library publication on the device.
     *
     * Opened here rather than handed in, the same way [mark] builds the stores it needs: it
     * is a thin wrapper over shared preferences and a directory, and threading it through
     * the app shell to reach one button in a bar would be a parameter carrying nothing.
     */
    private val downloads by lazy { DownloadStore.open(getApplication()) }

    /** Which publications already have a copy of their own. */
    fun keptOffline(): Set<String> = KeepOffline.kept(downloads)

    /** What a set of publications weighs, for the confirmation that has to state a size. */
    fun bytesOnDisk(ids: Set<String>): Long = KeepOffline.bytesOnDisk(
        resolver,
        _publications.value.filter { it.id in ids }.mapNotNull(::location),
    )

    /** Copies a whole selection into the download store, and reports what it copied. */
    suspend fun keepOffline(selection: Set<String>): Set<String> =
        KeepOffline.keep(resolver, downloads, _publications.value, selection, ::location)

    /** Forgets copies [keepOffline] made, deleting the files with them. */
    fun forgetKept(ids: Set<String>) = KeepOffline.forget(downloads, ids)

    fun removeFromCollection(members: Set<String>, id: UUID) {
        _shelves.update { it.removing(members, id) }
        shelvesStore?.save(_shelves.value)
    }

    // Bulk actions: the single-publication paths, applied to a set. Each answers with what
    // it changed rather than with nothing, because the undo is built from the change --
    // [BulkSelection] works out what that is, and these carry it out.

    /** Adds a whole selection to a collection. */
    fun addSelectionToCollection(selection: Set<String>, id: UUID): Set<String> {
        val collection = _shelves.value.collections.firstOrNull { it.id == id } ?: return emptySet()
        val joining = BulkSelection.joining(selection, collection)
        if (joining.isEmpty()) return emptySet()
        addToCollection(joining, id)
        return joining
    }

    /** Appends a whole selection to a reading list, in the order the library is showing it. */
    fun appendSelectionToList(selection: Set<String>, id: UUID): List<String> {
        val list = _shelves.value.lists.firstOrNull { it.id == id } ?: return emptyList()
        val entries = BulkSelection.appending(selection, list, _visible.value.map { it.id })
        if (entries.isEmpty()) return emptyList()
        appendToList(entries, id)
        return entries
    }

    /**
     * Deletes a shelf the reader has confirmed, and not one they have not.
     *
     * The only way a shelf leaves the app, and it takes a [ShelfDeletion] -- which can only be
     * answered by the dialogue that presents it. The two calls this replaced took a bare
     * identity, so a caller could delete a hand-built collection without asking, and one did.
     * `collections-and-reading-lists` requires the confirmation, and the signature is what
     * makes it required rather than remembered.
     */
    internal fun delete(deletion: ShelfDeletion) {
        _shelves.update { deletion.apply(it) }
        shelvesStore?.save(_shelves.value)
    }

    /**
     * Gives a collection a cover of its own, or hands it back to the composite with `null`.
     *
     * `collections-and-reading-lists` makes the composite what a collection wears "unless the
     * user sets a specific one". [Shelves.settingCover] has always been able to store the
     * choice; this is the first thing that asks it to.
     */
    fun setCollectionCover(member: String?, id: UUID) {
        _shelves.update { it.settingCover(member, id) }
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

    /**
     * What the reader came from, for `comic-reader`'s previous-chapter action.
     *
     * The mirror of [next] and resolved the same way, list before series: a reader who
     * arranged a crossover expects to walk back through their own order, not through the
     * issue numbers it cuts across.
     */
    fun previous(before: Publication): Publication? {
        val known = _publications.value
        for (list in _shelves.value.lists) {
            if (before.id !in list.entries) continue
            val previousId = list.previous(before.id) ?: continue
            known.firstOrNull { it.id == previousId }?.let { return it }
        }
        return LibraryIndex.previous(before, known)
    }
}
