package app.storyarc.feature.library

import android.net.Uri
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import java.util.UUID

/**
 * The folder source a tree belongs to, if it is registered as one.
 *
 * Matched on the tree's whole address, the same key `LibraryViewModel.register` uses. The
 * app's own managed folder is not a source, so a publication found there is unattributed --
 * the honest answer rather than pretending it belongs to a library the reader picked.
 */
internal fun SourceRegistry.folderSourceOf(tree: Uri?): UUID? {
    val locator = tree?.toString() ?: return null
    return sources
        .firstOrNull { it.kind == SourceKind.LOCAL_FOLDER && it.locator == locator }
        ?.id
}
