package app.storyarc.core.format

import app.storyarc.core.model.NaturalOrder

/** One page inside a publication, before it is decoded. */
data class PageEntry(
    /** The entry's path inside the archive. Unique, so it is the identity. */
    val path: String,
    /** Uncompressed size in bytes, where the container reports one. */
    val byteCount: Long? = null,
)

/**
 * Which archive entries are pages, and in what order.
 *
 * This is the part of the format layer most likely to disagree between the two
 * platforms, so it is pure, dependency-free, and asserted against the shared
 * fixture corpus on both. iOS's `PageOrdering` mirrors it line for line.
 */
object PageOrdering {
    /**
     * Image extensions StoryArc will attempt to decode. A file outside this set
     * is never a page — `publication-formats` requires `ComicInfo.xml`,
     * `Thumbs.db` and resource forks to be excluded rather than shown blank.
     *
     * `jxl` is in the list although neither platform's decoder reads it, and that is
     * deliberate: `publication-formats` requires an unsupported codec to show "a
     * placeholder naming the codec" without breaking pagination, and a page excluded
     * from the list is a page nobody can be told about. It is listed so it can be
     * refused by name — see [PageCodec].
     */
    val IMAGE_EXTENSIONS = setOf(
        "jpg", "jpeg", "png", "webp", "avif", "gif", "heic", "heif", "bmp", "tif", "tiff",
        "jxl",
    )

    /**
     * True when an entry could be part of a publication at all.
     *
     * Everything [isPage] rejected before it looked at the extension, split out so
     * [FolderKind] can apply the same exclusions to audio without restating them. A
     * resource fork is not evidence of a comic and not evidence of an audiobook
     * either, and two copies of that list would eventually disagree.
     */
    fun isCandidateEntry(path: String): Boolean {
        if (path.endsWith("/")) return false

        val components = path.split('/').filter { it.isNotEmpty() }
        val name = components.lastOrNull() ?: return false

        // macOS resource forks travel inside archives made on a Mac and mirror
        // every real page, so an archive would report double its page count.
        if (components.any { it == "__MACOSX" }) return false
        if (name.startsWith("._")) return false
        // Dotfiles: .DS_Store and friends.
        if (name.startsWith(".")) return false
        return true
    }

    /** True when an entry is a page candidate. */
    fun isPage(path: String): Boolean {
        if (!isCandidateEntry(path)) return false
        val name = path.split('/').filter { it.isNotEmpty() }.last()
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext in IMAGE_EXTENSIONS
    }

    /**
     * Sorts entries the way a human would: `page10` after `page9`, and chapter
     * directories in order, by comparing the full path.
     */
    fun sorted(entries: List<PageEntry>): List<PageEntry> =
        entries.sortedWith { lhs, rhs -> naturalCompare(lhs.path, rhs.path) }

    /** Filters to pages, then sorts. The whole job in one call. */
    fun pages(paths: List<String>): List<PageEntry> =
        sorted(paths.filter(::isPage).map { PageEntry(it) })

    /**
     * Natural-order comparison: runs of digits compare numerically, everything
     * else compares case-insensitively.
     *
     * The rule itself is [NaturalOrder.compare] in `:core:model`, because the library's
     * own ordering falls back to it too and the two must not drift. This name stays
     * because the page order is what the format layer's callers ask for.
     *
     * @return negative when [lhs] sorts first, positive when [rhs] does, 0 when equal.
     */
    fun naturalCompare(lhs: String, rhs: String): Int = NaturalOrder.compare(lhs, rhs)
}
