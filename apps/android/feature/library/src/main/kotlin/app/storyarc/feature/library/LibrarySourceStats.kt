package app.storyarc.feature.library

import java.util.UUID

/**
 * How many publications a source has put on the shelf.
 *
 * `sources` asks a source's detail screen for its "cached item count". Counted from what the
 * library actually found rather than remembered separately: two numbers that can disagree is
 * how a screen ends up claiming a source has titles it cannot open. It is a count of what was
 * *read*, which is why [isPartial] exists beside it.
 *
 * An extension rather than a member: `LibraryViewModel.kt` is at its recorded line-cap
 * ceiling (`scripts/line-cap.mjs`), and 22.1-smb-opds needed room there for the SMB and OPDS
 * continuation cursors beside `partialSources`.
 */
fun LibraryViewModel.itemCount(sourceId: UUID): Int = _publications.value.count { it.sourceId == sourceId }

/** Whether [itemCount] is a slice of what this source holds rather than the whole of it. */
fun LibraryViewModel.isPartial(sourceId: UUID): Boolean = sourceId in partialSources
