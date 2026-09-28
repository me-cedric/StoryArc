package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * Where a continuous scroll sits within its current page, kept only on this device.
 *
 * Not part of [ReadingProgress]: that record is what syncs (ADR-0006), and syncing a
 * sub-page fraction would compare two devices' idea of "the same page" down to a pixel
 * neither shares typography with. `comic-reader` only asks for this to survive "leaving
 * and returning" the reader, which a per-device blob already does, and the stored page
 * index is untouched by it either way. iOS's `ScrollOffsetMemory` is the same shape.
 */
@Serializable
data class ScrollOffsetMemory(private val byIdentity: Map<String, Float> = emptyMap()) {
    /** The fraction stored for a publication, or `null` when none has been. */
    fun fraction(identity: PublicationIdentity): Float? = byIdentity[identity.stableId]

    /** This memory, with a publication's fraction set or replaced. */
    fun remembering(identity: PublicationIdentity, fraction: Float): ScrollOffsetMemory =
        copy(byIdentity = byIdentity + (identity.stableId to fraction.coerceIn(0f, 1f)))
}
