package app.storyarc.feature.library

import android.net.Uri
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.UriSource
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.RememberedFiles
import app.storyarc.core.persistence.documentNameOf
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
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
    if (files.isEmpty()) return
    viewModelScope.launch {
        var changed = false
        for (uri in files) {
            if (withContext(Dispatchers.IO) { indexRememberedFile(uri, store) }) changed = true
        }
        if (changed) rebuild()
    }
}

private suspend fun LibraryViewModel.indexRememberedFile(uri: Uri, store: RememberedFiles): Boolean {
    val publication = runCatching {
        UriSource(resolver, uri).use { source ->
            val digest = PublicationIndexer.contentDigest(source)
            PublicationIndexer.index(
                source = source,
                name = documentNameOf(resolver, uri),
                identity = PublicationIdentity(contentDigest = digest),
            )
        }
    }.getOrNull()
    if (publication == null) {
        // Gone, or its grant has: a provider revokes one without telling anybody, and
        // `local-library` has no notice for a file a reader did not configure as a source.
        store.forget(uri)
        return false
    }
    locations[publication.id] = uri.toString()
    return adopt(publication, sourceId = RememberedFiles.SOURCE_ID)
}
