package app.storyarc.feature.library

import app.storyarc.core.model.PublicationIdentity
import java.util.UUID

/**
 * The identities of the publications one source currently holds.
 *
 * 10.12: captured before a removal's rows go, because the tombstone a later purge reads
 * cannot be asked what the source held once the rows are gone. [LibraryViewModel.unregister]
 * and [LibraryViewModel.forget] both call this immediately before
 * [app.storyarc.core.model.SourceRegistry.removing].
 */
internal fun LibraryViewModel.identitiesHeld(sourceId: UUID): List<PublicationIdentity> =
    _publications.value.filter { it.sourceId == sourceId }.map { it.identity }

/**
 * Forgets reading progress whose source has been gone for thirty days and whose book no
 * other source still holds.
 *
 * `sources` requires local reading progress to outlive a removed source "for 30 days", which
 * promises an end to retention as much as retention itself — and until this existed,
 * `SourceRegistry.collectingExpiredTombstones` had no caller on Android, so a removed
 * source's tombstone, and the reading-progress rows it gated, lived forever.
 *
 * Called once per launch, from [app.storyarc.HomeDestination]. Nothing expires between one
 * launch and the next that the previous launch's pass did not already collect.
 */
suspend fun LibraryViewModel.purgeExpiredTombstones(atEpochMillis: Long = System.currentTimeMillis()) {
    // An empty shelf while sources remain cannot say what those sources hold: the cached shelf
    // was missing, and no scan has finished. The purge waits for a launch that can tell.
    if (_publications.value.isEmpty() && _registry.value.sources.isNotEmpty()) return
    val (pruned, expired) = _registry.value.collectingExpiredTombstones(atEpochMillis)
    if (expired.isEmpty()) return
    _registry.value = pruned
    sourceStore?.save(pruned)

    val stillHeld = _publications.value.map { it.identity }
    for (tombstone in expired) {
        for (identity in tombstone.identities) {
            if (stillHeld.none { held -> held.matches(identity) }) {
                progressStore?.forget(identity)
            }
        }
    }
}
