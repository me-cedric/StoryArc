package app.storyarc.core.format

import app.storyarc.core.model.Publication
import java.io.File

/**
 * The cover a reader chose, kept where a cache clear cannot reach it.
 *
 * Task 2.1 of `cover-for-every-publication`. Two decisions out of `design.md` are built in
 * here rather than left to the caller, because a caller that got either of them wrong would
 * lose a reader's work silently:
 *
 * - **Keyed by the content digest.** `contentDigest` survives a rename and a move, and
 *   `stableId` does not: it is the normalised path, so a reader who reorganises their files
 *   would lose every cover they chose. Reorganising files is the normal life of a library.
 * - **Not in the cache directory.** `StorageUsage.clearCache` empties that, and a cover the
 *   reader chose is not a cache — nothing can recreate it. It goes under `filesDir`, which is
 *   the app's own data and which the system does not reclaim.
 *
 * Where there is no digest — a folder of images, a server row — the key falls back to the
 * stable identifier, and [keyKind] says which was used so the publication page can state
 * plainly that moving this one loses the choice. A silent loss would be worse than a stated
 * limit. iOS's `CoverOverrideStore.swift` is its twin.
 *
 * @param directory where the images are kept. The caller decides, because this module has no
 *   `Context`; `LibraryViewModel.coverOverrideDirectory` is the production answer.
 */
class CoverOverrideStore(private val directory: File) {

    companion object {
        /**
         * Where chosen covers live, under an app's own data directory.
         *
         * [dataDir] is `Context.filesDir` and never `cacheDir`, and that distinction is the
         * whole of task 2.5: `StorageUsage.clearCache` empties the cache directories, and this
         * must survive that. Named here rather than written out at each call site so the two
         * callers — the library and the car shelf — cannot disagree about where a reader's
         * covers are.
         */
        fun directoryIn(dataDir: File): File = File(dataDir, "cover-overrides")
    }

    /** Which identity a publication's override is filed under. */
    enum class Key {
        /** The content digest: survives a rename and a move. */
        CONTENT_DIGEST,

        /** The stable identifier: the publication's own path, so moving it loses the choice. */
        STABLE_IDENTIFIER,
    }

    /** Which identity this publication's override is filed under. */
    fun keyKind(publication: Publication): Key =
        if (publication.identity.contentDigest == null) Key.STABLE_IDENTIFIER else Key.CONTENT_DIGEST

    /** The chosen cover's own file, or null where the reader has chosen none. */
    fun file(publication: Publication): File? = location(publication).takeIf { it.isFile }

    /** The chosen cover's bytes, or null where the reader has chosen none. */
    fun bytes(publication: Publication): ByteArray? =
        file(publication)?.let { runCatching { it.readBytes() }.getOrNull() }

    /**
     * Records [data] as this publication's cover, replacing whatever was chosen before.
     *
     * @return the file it wrote, or null when the write failed. A caller that got null should
     *   say so: unlike a cache write, this one is the reader's own choice, and dropping it
     *   quietly would leave them tapping a button that does nothing.
     */
    fun store(data: ByteArray, publication: Publication): File? {
        directory.mkdirs()
        val file = location(publication)
        // Written beside and renamed into place, as iOS's atomic write does. Written straight
        // to the final file, a write that failed part of the way deleted the earlier choice
        // and left a truncated image the store still reported as chosen.
        val partial = File(directory, "${file.name}.partial")
        return runCatching {
            partial.writeBytes(data)
            check(partial.renameTo(file)) { "rename failed" }
            file
        }.onFailure { partial.delete() }.getOrNull()
    }

    /**
     * Forgets this publication's chosen cover and deletes the image.
     *
     * `cover-art`'s *Undoing the choice*: the ladder resolves the cover again from the rung
     * below, and the stored image is deleted rather than orphaned.
     */
    fun remove(publication: Publication) {
        location(publication).delete()
    }

    /** Every chosen cover, by byte count, for the storage page. */
    fun sizeOnDisk(): Long =
        directory.walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    /**
     * Hashed rather than spelled out, for the reason [CoverCache] already gives: a stable
     * identifier is a path, a path carries separators, and a file name is not a place to find
     * that out. The key's own kind is folded in so a publication that gains a digest later
     * cannot read back the file its path wrote.
     */
    private fun location(publication: Publication): File {
        val identity = publication.identity
        val key = identity.contentDigest?.let { "sha:$it" } ?: identity.stableId
        var hash = -0x340d631b7bdddcdbL // FNV-1a offset basis
        key.toByteArray().forEach { byte -> hash = (hash xor byte.toLong()) * 0x100000001b3L }
        return File(directory, hash.toString(36))
    }
}
