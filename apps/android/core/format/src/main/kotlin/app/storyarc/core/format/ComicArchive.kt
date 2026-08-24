package app.storyarc.core.format

import java.io.File

/**
 * Reading pages out of a comic archive.
 *
 * `suspend` throughout because the bytes may be arriving from an SMB share or an
 * HTTP range request — ADR-0008 makes the source an abstraction, and this is the
 * layer that stops caring where pages come from.
 *
 * `publication-formats` requires a corrupt archive to yield whatever pages can
 * be read plus a count of what was skipped, rather than refusing the whole
 * publication.
 */
interface ComicArchiveReading : AutoCloseable {
    val pages: List<PageEntry>

    /** Entries that looked like pages but could not be read. */
    val skippedPageCount: Int

    /** Raw bytes for one page. */
    suspend fun data(page: PageEntry): ByteArray

    override fun close() {}
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
 */
class ZipComicArchive private constructor(
    private val source: RandomAccessSource,
    private val reader: ZipReader,
    override val pages: List<PageEntry>,
    override val skippedPageCount: Int,
    /** `ComicInfo.xml` contents when the archive carries one. */
    val comicInfoData: ByteArray?,
    private val pathToEntry: Map<String, ZipEntry>,
) : ComicArchiveReading {

    companion object {
        suspend fun open(source: RandomAccessSource): ZipComicArchive {
            val reader = try {
                ZipReader.open(source)
            } catch (_: ZipException.NoCentralDirectory) {
                // A ZIP whose central directory is gone. Our own reader makes
                // forward-scanning recovery *possible* — see ADR-0008 — but that
                // is not implemented yet, so this stays honest rather than
                // optimistic.
                throw ComicArchiveException.Unreadable()
            }

            val candidates = mutableListOf<PageEntry>()
            val index = mutableMapOf<String, ZipEntry>()
            var skipped = 0
            var comicInfo: ZipEntry? = null

            for (entry in reader.entries) {
                if (entry.path.lowercase().endsWith("comicinfo.xml")) {
                    comicInfo = entry
                    continue
                }
                if (!PageOrdering.isPage(entry.path)) continue
                if (entry.isEncrypted) {
                    // `publication-formats`: state that the archive is protected
                    // rather than prompting. One encrypted page means it is.
                    throw ComicArchiveException.PasswordProtected()
                }
                // A zero-length entry is a page that will never decode. Counting
                // it as skipped is what lets the reader say "opened 10, skipped 2".
                if (entry.uncompressedSize == 0L) {
                    skipped++
                    continue
                }
                candidates += PageEntry(entry.path, entry.uncompressedSize)
                index[entry.path] = entry
            }

            return ZipComicArchive(
                source = source,
                reader = reader,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                comicInfoData = comicInfo?.let { reader.data(it) },
                pathToEntry = index,
            )
        }
    }

    override suspend fun data(page: PageEntry): ByteArray {
        val entry = pathToEntry[page.path] ?: throw ComicArchiveException.Unreadable()
        return reader.data(entry)
    }

    /**
     * Every page's bytes, skipping any that fail. Used by the indexer, which
     * needs a cover and cannot afford to abort on one bad entry.
     */
    suspend fun readableData(pages: List<PageEntry>): List<Pair<PageEntry, ByteArray>> =
        pages.mapNotNull { page -> runCatching { page to data(page) }.getOrNull() }

    override fun close() = source.close()
}


/**
 * A CBT. TAR carries no compression and no encryption, so opening one is header
 * parsing and nothing else — see [TarReader] for why this needs no C.
 */
class TarComicArchive private constructor(
    private val source: RandomAccessSource,
    private val reader: TarReader,
    override val pages: List<PageEntry>,
    override val skippedPageCount: Int,
    /** `ComicInfo.xml` contents when the archive carries one. */
    val comicInfoData: ByteArray?,
    private val pathToEntry: Map<String, TarEntry>,
) : ComicArchiveReading {

    companion object {
        suspend fun open(source: RandomAccessSource): TarComicArchive {
            val reader = try {
                TarReader.open(source)
            } catch (_: TarException.NotTar) {
                throw ComicArchiveException.UnrecognisedContainer()
            } catch (_: TarException.Malformed) {
                throw ComicArchiveException.Unreadable()
            }

            val candidates = mutableListOf<PageEntry>()
            val index = mutableMapOf<String, TarEntry>()
            var skipped = 0
            var comicInfo: TarEntry? = null

            for (entry in reader.entries) {
                if (entry.path.lowercase().endsWith("comicinfo.xml")) {
                    comicInfo = entry
                    continue
                }
                if (!PageOrdering.isPage(entry.path)) continue
                // A zero-length entry is a page that will never decode. Counting
                // it as skipped is what lets the reader say "opened 10, skipped 2".
                if (entry.size == 0L) {
                    skipped++
                    continue
                }
                candidates += PageEntry(entry.path, entry.size)
                index[entry.path] = entry
            }

            return TarComicArchive(
                source = source,
                reader = reader,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                comicInfoData = comicInfo?.let { reader.data(it) },
                pathToEntry = index,
            )
        }
    }

    override suspend fun data(page: PageEntry): ByteArray {
        val entry = pathToEntry[page.path] ?: throw ComicArchiveException.Unreadable()
        return reader.data(entry)
    }

    override fun close() = source.close()
}

/** Opens whatever a file turns out to be. */
object ComicArchiveOpener {
    /** Sniffs the container, then opens it. Extension is never trusted. */
    suspend fun open(source: RandomAccessSource): ComicArchiveReading {
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)
        return when (val container = FormatSniffer.container(probe)) {
            FormatSniffer.Container.ZIP -> ZipComicArchive.open(source)
            FormatSniffer.Container.TAR -> TarComicArchive.open(source)
            // `publication-formats` requires a *named* refusal, never a generic
            // parse failure — `Container.displayName` is what carries the name.
            // RAR needs a decoder (ADR-0005), 7-Zip is out of scope, and PDF has
            // its own reader rather than an archive one.
            FormatSniffer.Container.RAR,
            FormatSniffer.Container.SEVEN_ZIP,
            FormatSniffer.Container.PDF,
            -> throw ComicArchiveException.UnsupportedContainer(container)
            null -> throw ComicArchiveException.UnrecognisedContainer()
        }
    }

    /** Convenience for a local file — the only source type that exists today. */
    suspend fun open(file: File): ComicArchiveReading = open(FileSource(file))
}
