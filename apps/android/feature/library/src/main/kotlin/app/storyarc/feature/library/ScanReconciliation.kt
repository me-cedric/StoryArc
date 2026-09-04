package app.storyarc.feature.library

import java.util.UUID

/**
 * What a finished scan takes off the shelf.
 *
 * A walk that found nothing is far more likely to be a folder it could not read — a
 * permission dropped, a share offline, a card pulled — than a reader who deleted every book
 * they own, and `sources` promises cached content "remains browsable" when a source is
 * unreachable. So a walk that saw nothing removes nothing.
 *
 * **That was inference, and the walk now reports the fact.** Guessing from an empty result
 * only covers the folder that became unreadable *whole*; a folder that lost one subdirectory
 * still returns rows, and every book under the branch it could not list looked deleted.
 * `LibraryScanner`'s `onUnreadableFolder` says which scopes could not account for themselves,
 * and [partial] is where that answer arrives.
 *
 * **That rule used to be asked of the whole scan at once, and once the app's own folder
 * started being walked alongside the picked ones that stopped being safe.** One readable
 * folder answering would have licensed the removal of every book in a folder whose
 * permission had lapsed, because the scan as a whole had "seen something". The question is
 * per source: a source whose own walk found nothing is a source with nothing to say about
 * what it still holds.
 *
 * The same rule keeps a folder walk away from rows it never walks at all. A chapter kept
 * from a Kavita server is attributed to that server, no folder walk can meet it, and before
 * this it went the first time any folder scan finished — which is the shelf losing a
 * download because an unrelated directory was read.
 *
 * Pure, so the four cases are asserted without an `Application`. The same split
 * [SourceRemoval] makes.
 */
internal object ScanReconciliation {

    /**
     * The publications to drop.
     *
     * @param seenBySource what each walk met, keyed by the source it belongs to. `null` is
     *   the app's own managed folder, which is not a source. **Every walked scope needs an
     *   entry**, empty or not — an absent key is a source that was never walked, and its
     *   rows stay.
     * @param shelved every publication on the shelf now, as its id and the source it came
     *   from.
     * @param partial the scopes whose walk met a directory it could not list.
     *
     *   A walk that found *something* and could not read one subdirectory is not a walk that
     *   can account for the whole source. The empty-set rule above catches the folder whose
     *   permission lapsed entirely; this catches the folder that lost one branch of itself,
     *   and without it the books under that branch are removed as though the reader had
     *   deleted them. `LibraryScanner` reports it per directory for exactly this reason.
     * @return the ids to remove, in shelf order.
     */
    fun vanished(
        seenBySource: Map<UUID?, Set<String>>,
        shelved: List<Pair<String, UUID?>>,
        partial: Set<UUID?> = emptySet(),
    ): List<String> {
        val answered = seenBySource.filterValues { it.isNotEmpty() }.keys - partial
        val seen = seenBySource.values.flatten().toSet()
        return shelved
            .filter { (id, source) -> source in answered && id !in seen }
            .map { it.first }
    }
}
