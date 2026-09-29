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
 *
 * **Kept with the page it belongs to.** A fraction on its own was restored onto whichever
 * page the reader opened on: a position synced from another device, or a page turned to
 * in another mode, took the fraction of a page it had never been on.
 */
@Serializable
data class ScrollOffsetMemory(private val byIdentity: Map<String, Entry> = emptyMap()) {
    /** Where a scroll stopped: the page, and how far through it. */
    @Serializable
    data class Entry(val page: Int, val fraction: Float)

    /** Where a publication's scroll last stopped, or `null` when it never did. */
    fun entry(identity: PublicationIdentity): Entry? = byIdentity[identity.stableId]

    /** This memory, with a publication's stopping place set or replaced. */
    fun remembering(identity: PublicationIdentity, fraction: Float, page: Int): ScrollOffsetMemory =
        copy(byIdentity = byIdentity + (identity.stableId to Entry(page, fraction.coerceIn(0f, 1f))))
}
