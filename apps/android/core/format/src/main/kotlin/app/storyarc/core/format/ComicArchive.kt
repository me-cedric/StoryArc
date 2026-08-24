package app.storyarc.core.format

import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipFile

/**
 * Reading pages out of a comic archive.
 *
 * `publication-formats` requires a corrupt archive to yield whatever pages can
 * be read plus a count of what was skipped, rather than refusing the whole
 * publication — so nothing here throws on a damaged entry.
 */
interface ComicArchiveReading : AutoCloseable {
    val pages: List<PageEntry>

    /** Entries that looked like pages but could not be read. */
    val skippedPageCount: Int

    /** Raw bytes for one page. */
    fun data(page: PageEntry): ByteArray
}

sealed class ComicArchiveException(message: String) : Exception(message) {
    /** The container is one StoryArc recognises but cannot read yet. */
    class UnsupportedContainer(val container: FormatSniffer.Container) :
        ComicArchiveException("unsupported container: $container")

    /** Nothing recognisable at all. */
    class UnrecognisedContainer : ComicArchiveException("unrecognised container")

    /**
     * The archive needs a password. `publication-formats` requires StoryArc to
     * say so rather than prompt, because it does not manage archive passwords.
     */
    class PasswordProtected : ComicArchiveException("archive is password protected")

    /** Not a single entry could be read, damaged beyond partial recovery. */
    class Unreadable : ComicArchiveException("archive is unreadable")
}

/**
 * A CBZ, or anything else that turns out to be a ZIP — including a file named
 * `.cbr` that is really a ZIP, which the format spec requires to open.
 *
 * Uses `java.util.zip.ZipFile` from the standard library. iOS needs a dependency
 * here because Apple platforms ship no ZIP container reader; Android does not.
 */
class ZipComicArchive(file: File) : ComicArchiveReading {
    private val zip: ZipFile = try {
        ZipFile(file)
    } catch (_: ZipException) {
        // A ZIP whose central directory is gone lands here. `ZipFile` offers no
        // partial-recovery path, so this is the honest answer: the file is
        // unreadable, and the caller reports that rather than pretending it opened.
        throw ComicArchiveException.Unreadable()
    }

    override val pages: List<PageEntry>
    override val skippedPageCount: Int

    /** `ComicInfo.xml` contents when the archive carries one. */
    val comicInfoData: ByteArray?

    init {
        val candidates = mutableListOf<PageEntry>()
        var skipped = 0
        var comicInfo: ByteArray? = null

        for (entry in zip.entries()) {
            val path = entry.name
            if (path.lowercase().endsWith("comicinfo.xml")) {
                comicInfo = runCatching { zip.getInputStream(entry).use { it.readBytes() } }.getOrNull()
                continue
            }
            if (!PageOrdering.isPage(path)) continue
            // A zero-length entry is a page that will never decode. Counting it
            // as skipped is what lets the reader say "opened 10, skipped 2".
            if (entry.size == 0L) {
                skipped++
                continue
            }
            candidates += PageEntry(path, entry.size.takeIf { it >= 0 })
        }

        pages = PageOrdering.sorted(candidates)
        skippedPageCount = skipped
        comicInfoData = comicInfo
    }

    override fun data(page: PageEntry): ByteArray {
        val entry: ZipEntry = zip.getEntry(page.path) ?: throw ComicArchiveException.Unreadable()
        return zip.getInputStream(entry).use { it.readBytes() }
    }

    /**
     * Every page's bytes, skipping any that fail. Used by the indexer, which
     * needs a cover and cannot afford to abort on one bad entry.
     */
    fun readableData(pages: List<PageEntry>): List<Pair<PageEntry, ByteArray>> =
        pages.mapNotNull { page -> runCatching { page to data(page) }.getOrNull() }

    override fun close() = zip.close()
}

/** Opens whatever a file turns out to be. */
object ComicArchiveOpener {
    /** Sniffs the container, then opens it. Extension is never trusted. */
    fun open(file: File): ComicArchiveReading = when (val container = FormatSniffer.container(file)) {
        FormatSniffer.Container.ZIP -> ZipComicArchive(file)
        // ADR-0005: the RAR decoder needs a licence review before it ships, and
        // CB7 needs a spike. Naming the container the user actually has is more
        // useful than a generic failure.
        FormatSniffer.Container.RAR,
        FormatSniffer.Container.SEVEN_ZIP,
        FormatSniffer.Container.PDF,
        -> throw ComicArchiveException.UnsupportedContainer(container)
        null -> throw ComicArchiveException.UnrecognisedContainer()
    }
}
