package app.storyarc.core.format

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
     */
    val IMAGE_EXTENSIONS = setOf(
        "jpg", "jpeg", "png", "webp", "avif", "gif", "heic", "heif", "bmp", "tif", "tiff",
    )

    /** True when an entry is a page candidate. */
    fun isPage(path: String): Boolean {
        if (path.endsWith("/")) return false

        val components = path.split('/').filter { it.isNotEmpty() }
        val name = components.lastOrNull() ?: return false

        // macOS resource forks travel inside archives made on a Mac and mirror
        // every real page, so an archive would report double its page count.
        if (components.any { it == "__MACOSX" }) return false
        if (name.startsWith("._")) return false
        // Dotfiles: .DS_Store and friends.
        if (name.startsWith(".")) return false

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
     * Written by hand rather than using a collator because collation is
     * locale-sensitive, and page order inside an archive must not depend on the
     * reader's language.
     *
     * @return negative when [lhs] sorts first, positive when [rhs] does, 0 when equal.
     */
    fun naturalCompare(lhs: String, rhs: String): Int {
        var left = 0
        var right = 0

        while (left < lhs.length && right < rhs.length) {
            val leftIsDigit = lhs[left].isDigit()
            val rightIsDigit = rhs[right].isDigit()

            if (leftIsDigit && rightIsDigit) {
                val leftEnd = runEnd(lhs, left)
                val rightEnd = runEnd(rhs, right)
                // Compared digit-by-digit rather than parsed into an integer:
                // parsing caps at the platform's word size, and Android's Long
                // and iOS's UInt64 do not have the same ceiling. A page number is
                // never that long, but a latent divergence between the two
                // implementations is exactly what this layer must not have.
                val leftDigits = lhs.substring(left, leftEnd).trimStart('0')
                val rightDigits = rhs.substring(right, rightEnd).trimStart('0')
                if (leftDigits.length != rightDigits.length) {
                    return leftDigits.length.compareTo(rightDigits.length)
                }
                if (leftDigits != rightDigits) return leftDigits.compareTo(rightDigits)
                // Same value. Fewer leading zeros sorts first, so the order is total.
                val leftRun = leftEnd - left
                val rightRun = rightEnd - right
                if (leftRun != rightRun) return leftRun.compareTo(rightRun)
                left = leftEnd
                right = rightEnd
                continue
            }

            // A digit sorts before a letter, so `p1` precedes `pa`.
            if (leftIsDigit != rightIsDigit) return if (leftIsDigit) -1 else 1

            val leftChar = lhs[left].lowercaseChar()
            val rightChar = rhs[right].lowercaseChar()
            if (leftChar != rightChar) return leftChar.compareTo(rightChar)
            left++
            right++
        }

        return (lhs.length - left).compareTo(rhs.length - right)
    }

    private fun runEnd(text: String, from: Int): Int {
        var index = from
        while (index < text.length && text[index].isDigit()) index++
        return index
    }
}
