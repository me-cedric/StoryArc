package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.CoverLoader
import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** What the library is doing, so the UI can say so rather than guess. */
sealed interface LibraryScanState {
    data object Idle : LibraryScanState

    /** A scan is running. The count is what `local-library` asks to be reported. */
    data class Scanning(val found: Int) : LibraryScanState

    data class Finished(val found: Int, val skipped: Int) : LibraryScanState
}

/**
 * The library's state and the work behind it.
 *
 * `local-library` requires a scan that reports progress, does not block browsing
 * what it has already found, and is cancellable. So publications are appended as
 * the scanner emits them and the screen recomposes each time, rather than waiting
 * for a finished list.
 *
 * iOS's `LibraryModel` is the same shape with `AsyncStream` in place of `Flow`.
 */
class LibraryViewModel(
    application: Application,
    private val progressStore: ProgressStore? = null,
) : AndroidViewModel(application) {

    private val _publications = MutableStateFlow<List<Publication>>(emptyList())
    val publications: StateFlow<List<Publication>> = _publications.asStateFlow()

    private val _scanState = MutableStateFlow<LibraryScanState>(LibraryScanState.Idle)
    val scanState: StateFlow<LibraryScanState> = _scanState.asStateFlow()

    private val covers = mutableMapOf<String, Bitmap>()
    /**
     * How far through each publication the reader got, keyed by publication id.
     *
     * A state map, so a cover's bar appears when the value arrives. Compose does
     * not observe a plain map — the reader learned that the hard way.
     */
    private val progress = androidx.compose.runtime.mutableStateMapOf<String, ReadingProgress>()
    private val locations = mutableMapOf<String, File>()
    private var scanJob: Job? = null

    /**
     * The folder StoryArc manages itself.
     *
     * `local-library`'s imported copies live here, and it needs no permission, so
     * it is the one folder the app can always read. A user reaches it over USB or
     * from a file manager.
     *
     * ponytail: the Storage Access Framework is the other half of that requirement
     * and is **not** here yet. SAF hands back a tree `Uri` rather than a path, so
     * it needs a `RandomAccessSource` backed by a `ParcelFileDescriptor` and a walk
     * over `DocumentFile` — a real piece of work, and doing it badly would be worse
     * than not yet having it. Until then a user can add books but not point at a
     * folder they already have.
     */
    val managedFolder: File
        get() = getApplication<Application>().getExternalFilesDir(null)
            ?: getApplication<Application>().filesDir

    fun scan(folder: File = managedFolder) {
        scanJob?.cancel()
        _publications.value = emptyList()
        covers.clear()
        locations.clear()
        _scanState.value = LibraryScanState.Scanning(0)

        scanJob = viewModelScope.launch {
            withContext(Dispatchers.IO) {
                LibraryScanner.scan(folder).collect { event ->
                    when (event) {
                        is ScanEvent.Found -> append(event.publication)
                        // Counted in the finished event. Not surfaced per file: a
                        // scan of a messy folder would be a wall of notices.
                        is ScanEvent.Skipped -> Unit
                        is ScanEvent.Finished ->
                            _scanState.value = LibraryScanState.Finished(event.found, event.skipped)
                    }
                }
            }
        }
    }

    /** Stops a running scan. `local-library` requires the scan to be cancellable. */
    fun cancelScan() {
        scanJob?.cancel()
        scanJob = null
        (_scanState.value as? LibraryScanState.Scanning)?.let {
            _scanState.value = LibraryScanState.Finished(it.found, 0)
        }
    }

    private fun append(publication: Publication) {
        // A publication already present is not added twice, and identity decides
        // that rather than the path — the same file reached two ways is one row
        // (ADR-0006).
        if (_publications.value.any { it.identity.matches(publication.identity) }) return

        publication.identity.normalizedPath?.let { locations[publication.id] = File(it) }
        _publications.update { it + publication }
        (_scanState.value as? LibraryScanState.Scanning)?.let {
            _scanState.value = LibraryScanState.Scanning(it.found + 1)
        }
    }

    /**
     * The fraction read, for a cover's progress indicator.
     *
     * `null` for a publication never opened — `library-browsing` wants an indicator
     * on a *partially read* cover, and a bar at zero on every unread book would be
     * noise rather than information.
     */
    fun readFraction(publication: Publication): Float? {
        val record = progress[publication.id] ?: return null
        if (record.isFinished) return 1f
        val fraction = record.position.fraction.toFloat()
        return if (fraction > 0f) fraction else null
    }

    /**
     * Reloads recorded positions. Called when the library appears, so returning
     * from the reader shows the page you reached.
     */
    fun refreshProgress() {
        val store = progressStore ?: return
        viewModelScope.launch {
            val records = runCatching { store.recent(limit = 500) }.getOrDefault(emptyList())
            progress.clear()
            for (publication in _publications.value) {
                records.firstOrNull { it.identity.matches(publication.identity) }
                    ?.let { progress[publication.id] = it }
            }
        }
    }

    /** Where a publication's file is, so the app layer can hand it to a reader. */
    fun location(publication: Publication): File? = locations[publication.id]

    /**
     * The cover for a publication, decoded once and remembered.
     *
     * Called by a cell as it appears, which is what makes extraction lazy. A
     * publication with no cover returns `null` rather than throwing: a missing
     * cover is a normal state and the cell draws a placeholder.
     */
    suspend fun cover(publication: Publication, maxPixelSize: Int): Bitmap? {
        covers[publication.id]?.let { return it }
        val file = locations[publication.id] ?: return null
        val bitmap = withContext(Dispatchers.IO) {
            runCatching { CoverLoader.anyCover(publication, file, maxPixelSize) }.getOrNull()
        } ?: return null
        covers[publication.id] = bitmap
        return bitmap
    }
}
