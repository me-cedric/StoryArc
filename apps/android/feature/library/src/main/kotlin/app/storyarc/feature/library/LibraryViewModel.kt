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
import app.storyarc.core.format.SafTree
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.LibraryPreferences
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
) : AndroidViewModel(application) {

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
    fun restoreFolders() {
        if (_folders.value.isNotEmpty()) return
        val restored = SafTree.persistedTrees(resolver)
        val reachable = restored.filter { SafTree.displayName(resolver, it) != null }
        _unavailableFolders.value = (restored - reachable.toSet()).map { nameOf(it) }
        if (reachable.isEmpty()) return
        _folders.value = reachable
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
        rescan()
    }

    /** Removes a folder and gives its permission back. */
    fun removeFolder(tree: Uri) {
        _folders.update { it - tree }
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
                val walks: List<Flow<ScanEvent>> =
                    if (trees.isEmpty()) {
                        listOf(LibraryScanner.scan(managedFolder))
                    } else {
                        trees.map { LibraryScanner.scan(resolver, it) }
                    }
                for (walk in walks) {
                    walk.collect { event ->
                        when (event) {
                            is ScanEvent.Found -> append(event.publication)
                            is ScanEvent.Skipped -> Unit
                            is ScanEvent.Finished -> {
                                found += event.found
                                skipped += event.skipped
                            }
                        }
                    }
                }
                _scanState.value = LibraryScanState.Finished(found, skipped)
                rebuild()
            }
            // After the walk, not before it. Recorded positions are matched against
            // the publications the scan produced, so refreshing while the list is
            // still empty matches nothing and every cover opens without its bar.
            refreshProgress()
        }
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

    private fun append(publication: Publication) {
        if (_publications.value.any { it.identity.matches(publication.identity) }) return

        publication.identity.normalizedPath?.let { locations[publication.id] = it }
        _publications.update { it + publication }
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
}
