package app.storyarc.core.model

import java.util.UUID

/**
 * What the storage view asks of a library of downloads: how much, from where, and which
 * ones are the biggest.
 *
 * `offline-downloads` asks the storage view to state the total "broken down by source" and
 * to offer "a largest-first list, each removable". Split out of [Download]'s own file for
 * the reason iOS's `DownloadLibraryStorage.swift` is its own file too. iOS carries the same
 * two answers.
 */

/**
 * Every finished download, largest first -- the order "what can I delete" is asked in.
 *
 * [ImportedCopies] already sorts this for imports alone; this is the same rule over every
 * finished download, not only the imported ones.
 */
val DownloadLibrary.largestFirst: List<Download>
    get() = finished.sortedByDescending { it.downloadedBytes }

/**
 * Finished bytes, summed per source. `null` keys a download with no source of its own.
 *
 * A map rather than a sorted list: the storage view names each source through its own
 * registry, which this type knows nothing about, so the naming and the ordering both
 * belong to the caller.
 */
val DownloadLibrary.bytesBySource: Map<UUID?, Long>
    get() = finished.groupBy { it.sourceId }.mapValues { (_, downloads) -> downloads.sumOf { it.downloadedBytes } }
