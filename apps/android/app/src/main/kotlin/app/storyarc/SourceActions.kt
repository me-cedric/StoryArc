package app.storyarc

import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore

/**
 * Deletes the files one source produced, and the records of them.
 *
 * The source itself stays. `sources` lists "remove downloads" as its own action beside
 * removing the source, and a reader freeing space before a flight has not asked to
 * disconnect their server — while removing the source *does* take its downloads, which is
 * why both call this.
 *
 * Here rather than in the view model because the download store belongs to this layer: the
 * view model owns the registry and the shelf, and a feature module that reached into the
 * download directory would own two things that can disagree. iOS's `StoryArcAppActions`
 * makes the same split.
 *
 * Returns the library without them, for the caller to hold. Nothing is written when the
 * source produced no downloads: a save that changes nothing still costs a write, and this
 * runs on the way out of every source removal.
 */
internal fun removeDownloads(
    source: Source,
    downloads: DownloadLibrary,
    store: DownloadStore,
    /**
     * What a Kavita server said about those downloads, which goes with them.
     *
     * Null for a caller with no context to open one -- the cards are keyed by publication, so
     * one left behind describes bytes nobody has rather than corrupting anything, but leaving
     * it behind would put a row in an offline search that opens nothing.
     */
    cards: KavitaCardStore? = null,
): DownloadLibrary {
    val (kept, removed) = downloads.removingAll(source.id)
    if (removed.isEmpty()) return downloads
    removed.forEach { store.remove(it) }
    store.save(kept)
    cards?.removeAll(source.id.toString())
    return kept
}
