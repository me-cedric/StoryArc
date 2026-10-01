package app.storyarc.feature.library

import android.content.Intent
import android.net.Uri
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.UriSource
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.RememberedFiles
import app.storyarc.core.persistence.documentNameOf
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Indexes every file another app handed over and the reader kept, the way the folder restore
 * does for a picked folder -- except these have no screen waiting on them, so one that no
 * longer resolves is forgotten rather than reported.
 *
 * 10.10: the counterpart of iOS's `scan(restored.files + places)` -- iOS attributes a
 * remembered file to no source at all, which Android cannot: `null` is the managed folder's
 * own scope ([app.storyarc.feature.library.folderSourceOf]), always walked on every scan, so
 * a row filed under it would read as unseen by that walk and be removed by it. Filed under
 * [RememberedFiles.SOURCE_ID] instead, a scope no scan ever walks.
 */
internal fun LibraryViewModel.restoreRememberedFiles() {
    val store = RememberedFiles.open(getApplication())
    val files = store.all()
    viewModelScope.launch {
        val kept = mutableSetOf<String>()
        var changed = false
        for (uri in files) {
            // Read off the main thread, adopted on it: `adopt` and `locations` belong to it.
            val publication = withContext(Dispatchers.IO) { indexRememberedFile(uri) }
            if (publication == null) {
                // Gone, or its grant has: a provider revokes one without telling anybody, and
                // `local-library` has no notice for a file a reader did not configure as a source.
                store.forget(uri)
                runCatching { resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                continue
            }
            kept += uri.toString()
            locations[publication.id] = uri.toString()
            if (adopt(publication, sourceId = RememberedFiles.SOURCE_ID)) changed = true
        }
        // A file forgotten, or one that fell off the list, goes from the shelf too: the cached
        // shelf put its row back, and no scan ever walks this source to take it away.
        val before = _publications.value.size
        _publications.update { list ->
            list.filterNot { it.sourceId == RememberedFiles.SOURCE_ID && locations[it.id] !in kept }
        }
        if (changed || _publications.value.size != before) rebuild()
    }
}

private suspend fun LibraryViewModel.indexRememberedFile(uri: Uri): Publication? = runCatching {
    UriSource(resolver, uri).use { source ->
        val digest = PublicationIndexer.contentDigest(source)
        PublicationIndexer.index(
            source = source,
            name = documentNameOf(resolver, uri),
            identity = PublicationIdentity(contentDigest = digest),
        )
    }
}.getOrNull()
