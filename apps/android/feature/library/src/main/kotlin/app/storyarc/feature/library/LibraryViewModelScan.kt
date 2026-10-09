package app.storyarc.feature.library

import android.net.Uri
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.ScanEvent
import app.storyarc.core.model.FolderSnapshot
import app.storyarc.core.model.Publication
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

// The folder walk, the downloads that join the shelf, and the rule for one row per publication.
//
// Moved out of `LibraryViewModel.kt` unchanged, as extensions on the view model, so that
// file stays under the 800-line cap. The state these read stays on the class.

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
fun LibraryViewModel.rescan() {
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
                            LibraryScanner.scan(managedFolder, onUnreadableFolder = unreadable, coverCacheDir = audiobookCoverCacheDir)
                    }
                    val tree = Uri.parse(target)
                    // Matched on the path, which is what a directory walk knows. A
                    // publication whose identity is a content digest is still filed
                    // under the document it came out of.
                    val done = resumed[target]
                        .orEmpty()
                        .mapNotNull { it.identity.normalizedPath }
                        .toSet()
                    tree to LibraryScanner.scan(resolver, tree, done, audiobookCoverCacheDir, unreadable)
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
            // The digests this walk computed, handed to the store that keeps reading
            // positions. A position written before digests existed carries a path alone,
            // so the first rename lost it; [ProgressStore.save] repairs that only when
            // the reader opens the book again, which a reader who tidies first never
            // does. Once, at the end, over the whole shelf: [ProgressStore.link] writes
            // only what is new, so a linked library writes nothing. It is not free --
            // `existing` queries by server key, then digest, then path, and stops at the
            // first hit, so a publication nobody has read costs two indexed lookups.
            // Nothing here digests anything. iOS does the same in `LibraryModel.scan`.
            for (publication in _publications.value) {
                progressStore?.link(publication.identity)
            }
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
fun LibraryViewModel.adoptDownloads() {
    val store = downloadStore ?: return
    viewModelScope.launch {
        val downloads = store.library()
        if (downloads.finished.isEmpty()) return@launch

        var added = false
        withContext(Dispatchers.IO) {
            LibraryScanner.scan(store.directory, coverCacheDir = audiobookCoverCacheDir).collect { event ->
                val publication = (event as? ScanEvent.Found)?.publication ?: return@collect
                val path = publication.identity.normalizedPath ?: return@collect
                val record = store.download(File(path), downloads) ?: return@collect
                if (!record.state.isFinished) return@collect
                // What the server said wins over what the file says, and the card also
                // names the row this file is a copy of. Both in [DownloadFold.described];
                // this is the one place every kept download passes through.
                val described = DownloadFold.described(publication, cards?.card(publication.id), record)
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
private fun LibraryViewModel.adopt(publication: Publication, sourceId: UUID?, path: String): Boolean {
    val seen = DownloadFold.rowFor(_publications.value, publication)
    if (seen != null) {
        if (_publications.value[seen].sourceId == null && sourceId != null) {
            _publications.update { current ->
                current.mapIndexed { index, existing ->
                    if (index == seen) existing.copy(sourceId = sourceId) else existing
                }
            }
        }
        // The row learns where its bytes are and keeps everything else, key included.
        locations[_publications.value[seen].id] = path
        return false
    }

    locations[publication.id] = path
    _publications.update { it + publication.copy(sourceId = sourceId) }
    return true
}

/** The source a tree belongs to. [folderSourceOf] holds the rule. */
internal fun LibraryViewModel.sourceOf(tree: Uri?): UUID? = _registry.value.folderSourceOf(tree)

fun LibraryViewModel.cancelScan() {
    scanJob?.cancel()
    scanJob = null
    // Written down rather than lost, which is what makes the next scan of this folder a
    // resumption instead of a repetition.
    scanningFolder?.let { journal?.record(scanned, it) }
    (_scanState.value as? LibraryScanState.Scanning)?.let {
        _scanState.value = LibraryScanState.Finished(it.found, 0)
    }
}

private fun LibraryViewModel.append(publication: Publication, tree: Uri? = null) {
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
internal fun LibraryViewModel.adopt(publication: Publication, sourceId: UUID?): Boolean {
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
        if (!LibraryMerge.replaces(sourceId, existing.sourceId, _registry.value.sources)) {
            return false
        }
        _publications.update { current ->
            current.mapIndexed { index, each ->
                if (index != seen) each else LibraryMerge.merged(each, publication, sourceId, existing.id in locations)
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

private const val REBUILD_EVERY = 24
