package app.storyarc.feature.library

import android.app.Application
import android.net.Uri
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.SafTree
import app.storyarc.core.model.Source
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceProbe
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// Adding, renaming, ordering, testing and removing the sources the library reads.
//
// Moved out of `LibraryViewModel.kt` unchanged, as extensions on the view model, so that
// file stays under the 800-line cap. The state these read stays on the class.

/**
 * Adds a picked folder.
 *
 * The caller takes the persistable permission before calling — it belongs to
 * the `Intent` result and cannot be recovered afterwards.
 */
fun LibraryViewModel.addFolder(tree: Uri) {
    if (tree in _folders.value) return
    _folders.update { it + tree }
    _unavailableFolders.update { it - nameOf(tree) }
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
internal fun LibraryViewModel.register(tree: Uri) {
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
    retireStaleFolderRows(name, locator) // 10.13
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
fun LibraryViewModel.addSource(source: Source) {
    if (_registry.value[source.id] != null) return
    _registry.update { it.adoptingOrReadding(source) }
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
fun LibraryViewModel.reconnectSource(source: Source) {
    _registry.update { it.replacing(source) }
    sourceStore?.save(_registry.value)
}

fun LibraryViewModel.renameSource(source: Source, name: String) {
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
fun LibraryViewModel.reorderSource(source: Source, later: Boolean) {
    _registry.update { it.moving(source.id, later) }
    sourceStore?.save(_registry.value)
}

/**
 * Forgets a folder's source, and remembers that it was forgotten.
 *
 * The tombstone is what keeps reading progress for thirty days, per `sources`. It is
 * left for the registry to collect rather than deleted here. 10.11: the rows go too, the
 * same way [forget] already drops them for every other source kind.
 */
private fun LibraryViewModel.unregister(tree: Uri) {
    val source = _registry.value.sources.firstOrNull {
        it.kind == SourceKind.LOCAL_FOLDER && it.locator == tree.toString()
    } ?: return
    _registry.update { it.removing(source.id, System.currentTimeMillis(), identitiesHeld(source.id)) }
    sourceStore?.save(_registry.value)
    dropRowsOf(source.id)
}

/**
 * Removes a source, its secret, and the folder behind it when it has one.
 *
 * The permission goes back, and the registry keeps a tombstone so reading progress
 * survives the thirty days the requirement promises. The downloads are gone by the time
 * this runs: the app layer deletes them — files, records and Kavita cards — *before*
 * calling this (`SettingsHost`'s `REMOVE`, through `removeDownloads`), because the
 * registry entry is what attributes a download to a source, and this method's own job is
 * the registry, the credential, the shelf and the 30-day tombstone. A comment here used
 * to say files on disk are never touched, and a reading of it as the whole story called
 * the confirmation dialog right when it was promising the opposite of what the button did.
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
fun LibraryViewModel.removeSource(source: Source, credentials: CredentialStore?) {
    val removal = SourceRemoval.of(source, _folders.value.map { it.toString() })
    removal.credentialReference?.let { credentials?.remove(it) }

    val tree = removal.folder?.let { named ->
        _folders.value.firstOrNull { it.toString() == named }
    }
    if (tree != null) {
        removeFolder(tree)
        return
    }
    if (source.kind == SourceKind.LOCAL_FOLDER) source.locator?.let(Uri::parse)?.let(::releaseFolderGrant) // 10.13
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
fun LibraryViewModel.testSource(source: Source, credentials: CredentialStore?, pins: CertificatePins) {
    if (!SourceProbe.isRemote(source.kind)) {
        _registry.update { it.marking(source.id, folderState(source)) }
        return
    }
    viewModelScope.launch {
        _registry.update { it.marking(source.id, SourceConnectionState.Connecting) }
        val application = getApplication<Application>().speakingReaderLanguage()
        val reason = application.getString(R.string.source_state_unauthorized)
        val encryption = application.getString(R.string.smb_error_encryption)
        val state = SourceHealth.probe(
            source,
            credentials,
            pins,
            System.currentTimeMillis(),
            reason,
            encryption,
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
fun LibraryViewModel.refreshSource(source: Source, credentials: CredentialStore?, pins: CertificatePins) {
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
fun LibraryViewModel.clearSourceCache(source: Source) {
    val gone = _publications.value.filter { it.sourceId == source.id }.map { it.id }
    if (gone.isEmpty()) return
    _publications.update { list -> list.filterNot { it.id in gone } }
    gone.forEach { covers.remove(it); locations.remove(it) }
    writeShelfThrough()
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
private fun LibraryViewModel.folderState(source: Source): SourceConnectionState {
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
 * stays. Its downloads are not this method's to touch and are already gone: the app layer
 * deleted them before [removeSource] was called, as that method's note says.
 */
private fun LibraryViewModel.forget(source: Source) {
    _registry.update { it.removing(source.id, System.currentTimeMillis(), identitiesHeld(source.id)) }
    sourceStore?.save(_registry.value)
    dropRowsOf(source.id)
    rebuild()
}

/** Removes a folder and gives its permission back. */
fun LibraryViewModel.removeFolder(tree: Uri) {
    _folders.update { it - tree }
    unregister(tree)
    releaseFolderGrant(tree)
    snapshots.remove(tree.toString())
    rescan()
    startWatching()
}
