package app.storyarc.feature.library

import android.net.Uri
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.persistence.documentNameOf
import app.storyarc.core.persistence.importing
import app.storyarc.core.persistence.imports
import app.storyarc.core.persistence.locationOf
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

// The copies the reader imported into app storage, and the "On this device" source that holds them.
//
// Moved out of `LibraryViewModel.kt` unchanged, as extensions on the view model, so that
// file stays under the 800-line cap. The state these read stays on the class.

/**
 * Copies a publication into app storage and puts it in the library.
 *
 * The copy is indexed the same way a scanned file is, through [PublicationIndexer], so
 * an imported comic carries the same title, series and cover a found one does. Indexing
 * the *copy* rather than the original is what makes the promise true: from here on the
 * library reads only bytes the app owns.
 */
fun LibraryViewModel.importFile(uri: Uri) {
    val store = downloadStore ?: return
    viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            runCatching { store.importing(resolver, uri, store.library()) }
        }
        val copy = result.getOrNull()
        if (copy == null) {
            // Named, not silent, and naming the format when that is why (10.8).
            val unsupported = result.exceptionOrNull() as? ImportedCopies.ImportException.Unsupported
            _importFailure.value = withContext(Dispatchers.IO) {
                ImportFailure(documentNameOf(resolver, uri), unsupported?.format)
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
fun LibraryViewModel.refreshImports() {
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
suspend fun LibraryViewModel.importedBytes(): Long {
    val store = downloadStore ?: return 0
    return withContext(Dispatchers.IO) {
        store.imports(store.library()).sumOf { it.downloadedBytes }
    }
}

private suspend fun LibraryViewModel.indexImport(file: File) {
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
 *
 * The name is [importedSourceName], asked again on every call because it is translated.
 */
private fun LibraryViewModel.registerImportedSource() {
    val named = importedSourceName()
    if (keptImportedSourceNamed(named)) return
    _registry.update {
        it.adding(
            Source(
                id = ImportedCopies.SOURCE_ID,
                displayName = named,
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
private fun LibraryViewModel.forgetImportedSource() {
    if (_registry.value[ImportedCopies.SOURCE_ID] == null) return
    _registry.update { it.discarding(ImportedCopies.SOURCE_ID) }
    sourceStore?.save(_registry.value)
}

/** What "On this device" points at, which is not a folder anyone picked. */
private const val IMPORTED_LOCATOR = "storyarc/imported"
