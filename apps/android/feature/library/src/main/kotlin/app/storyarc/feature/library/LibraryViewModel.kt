package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.CoverCache
import app.storyarc.core.format.SafTree
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
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.readerLocale
import java.util.Locale
import java.util.UUID
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.LibraryCache
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.Shelves
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ScanJournal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class LibraryViewModel(
    application: Application,
    internal val progressStore: ProgressStore? = null,
    private val preferences: LibraryPreferences? = null,
    internal val sourceStore: SourceStore? = null,
    internal val shelvesStore: ShelvesStore? = null,
    /**
     * Where copies the reader imported live. `local-library` asks for them to be kept in
     * "app-managed storage", and this store already owns exactly that -- see
     * [ImportedCopies].
     */
    internal val downloadStore: DownloadStore? = null,
    /**
     * What an interrupted scan wrote down. `local-library` requires a scan to be
     * "cancellable and resumable" -- see [ScanJournal] for why those are one promise.
     */
    internal val journal: ScanJournal? = null,
    /**
     * What a Kavita server said about the downloads it produced.
     *
     * Read when a download joins the shelf, so the row carries the server's description
     * rather than the file's -- which is what `kavita-server` requires whether or not the
     * server can be reached. Null for a view model built without one, the way every other
     * store here is optional.
     */
    internal val cards: KavitaCardStore? = null,
    /** The reader's saved server keys. Null reads no server. See [readServers]. */
    internal val credentials: CredentialStore? = null,
    /** The app-level download queue, the only writer of the download store. See [keepOffline]. */
    private val downloadQueue: DownloadQueue? = null,
    /**
     * The app's one pin set. 11.7: an OPDS row's cover is fetched through the same
     * origin-bound client the library read and the detail page already use, and a
     * catalogue behind a certificate the reader has pinned needs this to reach it.
     */
    private val pins: CertificatePins = CertificatePins(),
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

    internal val _shelves = MutableStateFlow(shelvesStore?.shelves() ?: Shelves())

    /** The reader's collections and reading lists. */
    val shelves: StateFlow<Shelves> = _shelves.asStateFlow()

    internal val _publications = MutableStateFlow<List<Publication>>(emptyList())
    val publications: StateFlow<List<Publication>> = _publications.asStateFlow()

    internal val _scanState = MutableStateFlow<LibraryScanState>(LibraryScanState.Idle)
    val scanState: StateFlow<LibraryScanState> = _scanState.asStateFlow()

    /**
     * Who started the source refresh that is running now, if one is.
     *
     * `sources`' *Refresh visibility*. Internal so [probeAndWait] can set it: the probe is
     * an extension in `SourceRetry.kt`, and Kotlin's `private` is file-scoped as Swift's is.
     */
    internal val _refreshing = MutableStateFlow<SourceRefreshOrigin?>(null)

    /** What the shelf's notice strip and its pull indicator both read. */
    val refreshing: StateFlow<SourceRefreshOrigin?> = _refreshing.asStateFlow()

    /** What the library could not open, and whether the reader has been told. */
    internal val _skipped = MutableStateFlow(SkippedPublications())
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
    internal val _visible = MutableStateFlow<List<Publication>>(emptyList())
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
    internal val _folders = MutableStateFlow<List<Uri>>(emptyList())
    val folders: StateFlow<List<Uri>> = _folders.asStateFlow()

    /**
     * Folders that were remembered and can no longer be reached.
     *
     * `local-library` requires naming the folder and offering a single action to
     * re-pick it, so the names are kept rather than the count.
     */
    internal val _unavailableFolders = MutableStateFlow<List<String>>(emptyList())
    val unavailableFolders: StateFlow<List<String>> = _unavailableFolders.asStateFlow()

    internal val covers = mutableMapOf<String, Bitmap>()
    internal val coverRevisions = mutableStateMapOf<String, Int>() // See [coverRevision].
    private val progress = mutableStateMapOf<String, ReadingProgress>()

    /**
     * Where each publication came from, as the string its identity carries: a
     * filesystem path, or a document `Uri` from a picked folder.
     */
    internal val locations = mutableMapOf<String, String>()
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

    internal val resolver get() = getApplication<Application>().contentResolver

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

            val origin = kavita?.resolvedOrigin(publication.id) ?: return@launch
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
        val origin = kavita?.resolvedOrigin(publication.id) ?: return false
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

    /** Every server's publications, adopted as a scanned file is. See [ServerLibrary]. */
    fun readServers(pins: CertificatePins) = viewModelScope.launch {
        val reading = ServerLibrary.read(
            _registry, credentials, pins, progressStore,
            progressStore?.let { KavitaProgressStore.open(getApplication()) },
        )
        adoptPartialSources(reading.partial, reading.opdsNext, reading.smbQueues, pins)
        RefreshConflicts.report(reading.conflicts)
        reading.rows.forEach { (publication, sourceId) -> adopt(publication, sourceId) }
        if (reading.rows.isEmpty()) return@launch
        rebuild()
        // And written down, which nothing did: the snapshot was written when a *folder*
        // walk finished, so a reader whose library is one server and no folders had
        // nothing cached and opened the app offline to an empty shelf.
        //
        // It does not claim the shelf is fresh. This runs beside the folder walk, not
        // after it, so clearing the indicator here would answer for a walk that may still
        // be going -- and one that met an unreadable directory has refreshed nothing.
        shelfCache.write(_publications.value, locations.toMap(), partial = false, claimsFreshness = false)
    }

    /**
     * Re-opens the folders from a previous launch and scans them.
     *
     * Called once, when the library first appears. The permissions themselves come
     * back from the system, so this only has to decide which of them still point at
     * something readable.
     */
    fun restoreFolders(pins: CertificatePins) {
        if (_folders.value.isNotEmpty()) return
        // Before anything is walked, and before any early return below. `sources` asks for
        // the cached catalogue "within 500 ms of the library view appearing", and the walk
        // that follows corrects it in place.
        restoreCachedLibrary()
        readServers(pins)
        watchSourceReachability()
        restoreRememberedFiles() // 10.10

        val restored = SafTree.persistedTrees(resolver)
        val reachable = restored.filter { SafTree.displayName(resolver, it) != null }
        _folders.value = reachable
        // Connection state is never persisted, so a restored folder loads as *connecting*
        // and stays there — nothing probes a folder. [register] is what answers, and it also
        // corrects a name an older build derived. It adds nothing: a persisted tree
        // permission is one a reader picked, so it is already a source.
        reachable.forEach(::register)
        refreshFolderAvailability(restored, reachable) // 10.1
        // Even with no folder to restore: the app's own folder is walked on every scan, and
        // it is where a file shared to StoryArc lands.
        rescan()
        startWatching()
    }

    // [itemCount] and [isPartial] moved to `LibrarySourceStats.kt`: this file is at its
    // recorded line-cap ceiling (`scripts/line-cap.mjs`), and 22.1-smb-opds needs the two
    // continuation-cursor properties below it.

    /** Sources whose last read stopped at its own limit. [SourceSlice] explains what that is. */
    internal var partialSources: Map<UUID, SourceReadProgress> by mutableStateOf(emptyMap())

    /** A partial share's remaining walk frontier. [SmbContributor.page] resumes from it. */
    internal var smbQueues: Map<UUID, List<String>> by mutableStateOf(emptyMap())

    /** A partial catalogue's next feed link. [OpdsContributor.page] resumes from it. */
    internal var opdsNext: Map<UUID, String> by mutableStateOf(emptyMap())

    /**
     * The folder being walked, and what has been indexed in it so far.
     *
     * Held so an interrupted scan can be written down and picked up. `local-library` requires
     * a scan to be "cancellable and resumable", which are one promise: a reader who stops a
     * scan and starts it again should not wait for the same archives twice.
     */
    internal var scanningFolder: String? = null
    internal var scanned: MutableList<Publication> = mutableListOf()

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
    internal val snapshots = mutableMapOf<String, FolderSnapshot>()

    internal val watcher = FolderWatcher(resolver)

    override fun onCleared() {
        watcher.stop()
        super.onCleared()
    }

    // Imported copies

    /**
     * The last import that did not happen, named so the reader can be told which file.
     *
     * `local-library` forbids a generic failure elsewhere and there is no reason an import
     * should be the exception: a reader who picked the wrong file needs to know it was the
     * file rather than the app.
     */
    internal val _importFailure = MutableStateFlow<ImportFailure?>(null)
    val importFailure: StateFlow<ImportFailure?> = _importFailure.asStateFlow()

    fun dismissImportFailure() {
        _importFailure.value = null
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

    /**
     * The language the reader chose, or the device's when they have chosen none.
     *
     * Read on every rebuild rather than held: a reader who changes the language keeps this view
     * model -- `recreate()` retains it -- and a locale captured at construction would leave the
     * shelf collated in the language they just left.
     */
    internal fun readerLocale(): Locale = getApplication<Application>().readerLocale()

    /** Recomputes what is on screen from the library and the query. */
    internal fun rebuild() {
        val all = withSeriesStatuses(_publications.value)
        // The reader's language, not the device's. `localization` moves the interface to the
        // chosen language, and collation is part of the interface.
        val locale = readerLocale()
        _visible.value = LibraryIndex.arrange(all, _query.value, locale, ::stateOf)
        _matchGroups.value = LibraryIndex.grouped(all, _query.value, locale, ::stateOf)
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
    internal val coverCache by lazy { CoverCache(File(getApplication<Application>().cacheDir, "covers")) }

    /**
     * Last session's shelf, so opening the app does not mean walking every folder before
     * anything appears. [LibraryShelfCache] holds the file and the moment alike.
     */
    internal val shelfCache by lazy {
        LibraryShelfCache(LibraryCache(File(getApplication<Application>().cacheDir, "library.json")))
    }

    /** When the shelf on screen was last confirmed, while it is still the cached one. */
    val cachedAt: StateFlow<Long?> get() = shelfCache.cachedAt

    /**
     * Puts last session's shelf back before anything is walked.
     *
     * What follows is a scan, which appends to this rather than replacing it and removes
     * only what it can prove is gone — so the reader sees their library at once and watches
     * it correct itself, instead of watching it appear.
     */
    internal fun restoreCachedLibrary() {
        if (_publications.value.isNotEmpty()) return
        val snapshot = shelfCache.restore() ?: return
        _publications.value = snapshot.publications
        locations.putAll(snapshot.locations)
        rebuild()
    }

    /**
     * Records the shelf as it now stands, for the next launch.
     *
     * Called when a walk finishes rather than as publications arrive: a snapshot written
     * mid-scan is a half-library, and restoring one would show a shelf missing books for no
     * reason a reader could see.
     */
    internal fun cacheLibrary(partial: Boolean = false, claimsFreshness: Boolean = true) =
        shelfCache.write(_publications.value, locations.toMap(), partial, claimsFreshness)

    suspend fun cover(publication: Publication, maxPixelSize: Int): Bitmap? {
        covers[publication.id]?.let { return it }
        @Suppress("NAME_SHADOWING") val publication = catalogueIfOnShare(publication)

        chosenCover(publication, maxPixelSize)?.let { return it }
        withContext(Dispatchers.IO) { coverCache.bitmap(publication.id, maxPixelSize) }?.let {
            covers[publication.id] = it
            return it
        }

        val path = locations[publication.id] ?: return ServerLibrary
            .cachedCover(publication, _registry.value.sources, credentials, pins, covers) {
                coverCache.store(it, publication.id, maxPixelSize)
            }
        val bitmap = withContext(Dispatchers.IO) {
            ladderCover(publication, path, maxPixelSize)
                ?.also { coverCache.store(it, publication.id, maxPixelSize) }
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
    fun bytesOnDisk(ids: Set<String>): Long =
        KeepOffline.bytesOnDisk(resolver, _publications.value.filter { it.id in ids }, ::location)

    /** Copies a whole selection into the download store, and reports what it copied. */
    suspend fun keepOffline(selection: Set<String>): Set<String> =
        KeepOffline.keep(
            resolver, downloads, _publications.value, selection, ::location, downloadQueue,
            registry = _registry.value, credentials = credentials,
            context = getApplication(), kavita = KavitaProgressStore.open(getApplication()),
        )

    /** Forgets copies [keepOffline] made, deleting the files with them. */
    fun forgetKept(ids: Set<String>) = KeepOffline.forget(downloads, ids, downloadQueue)
}
