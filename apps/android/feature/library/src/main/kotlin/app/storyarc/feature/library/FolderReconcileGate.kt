package app.storyarc.feature.library

import app.storyarc.core.model.FolderSnapshot

/**
 * Whether a reconcile may act on a tree, given whatever snapshot it currently holds.
 *
 * 10.4: `null` means the running scan owns this tree -- its first walk has not finished and
 * written a snapshot yet. `reconcile` used to fall back to an empty `FolderSnapshot` here,
 * which compared every real file to nothing and reported each one "added": a provider
 * notification, or a return from the reader, during that first walk re-indexed the whole
 * tree a second time, in parallel with the scan already doing it.
 */
internal fun mayReconcile(snapshot: FolderSnapshot?): Boolean = snapshot != null
