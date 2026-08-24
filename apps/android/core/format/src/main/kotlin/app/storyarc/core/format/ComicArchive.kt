package app.storyarc.core.format

import android.content.ContentResolver
import android.net.Uri

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

    /**
     * The page to show as the publication's cover.
     *
     * `publication-formats`: the first page in reading order, *unless*
     * `ComicInfo.xml` designates a different one. Containers that carry no
     * metadata keep this default.
     */
    val coverPage: PageEntry?
        get() = pages.firstOrNull()

    override fun close() {}
}

/**
 * Resolves which page is the cover.
 *
 * Its own object rather than a method because every container needs the same rule
 * and only some of them carry the metadata that can change it. Keeping it in one
 * place is what stops a CBZ and a CBT disagreeing about which page a reader sees
 * first.
 */
object CoverSelection {
    /**
     * The designated cover, when one is designated and exists; otherwise the first
     * page in reading order.
     *
     * A designated index outside the page list is ignored rather than clamped.
     * [ComicInfo]'s indices count *archive* entries, and an archive whose non-page
     * entries were filtered out can leave a stale index behind — showing an
     * arbitrary middle page would look like a bug in the reader rather than in the
     * file.
     */
    fun cover(pages: List<PageEntry>, designated: Int?): PageEntry? {
        if (designated == null || designated < 0 || designated >= pages.size) {
            return pages.firstOrNull()
        }
        return pages[designated]
    }
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

    /**
     * A solid archive that cannot be read at all. Named separately from
     * [UnsupportedContainer] because the container *is* supported and this
     * particular file still cannot be read.
     *
     * Solid RAR4 only. libarchive reads a solid RAR5 completely; it refuses a
     * solid RAR4 outright. See the finding in the format change's task list.
     */
    class SolidArchive : ComicArchiveException("archive uses solid compression")
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
    /**
     * True when the archive's index was rebuilt by scanning, because its central
     * directory was gone. The pages are real; the count may be short.
     */
    val isRecovered: Boolean,
) : ComicArchiveReading {

    /** The archive's parsed metadata, when it carries any. */
    val comicInfo: ComicInfo? by lazy { comicInfoData?.let(ComicInfo::parse) }

    override val coverPage: PageEntry?
        get() = CoverSelection.cover(pages, comicInfo?.coverPageIndex)

    companion object {
        suspend fun open(source: RandomAccessSource): ZipComicArchive {
            val reader = try {
                ZipReader.open(source)
            } catch (_: ZipException.NoCentralDirectory) {
                // A ZIP whose central directory is gone — a truncated download, a
                // partial copy. `publication-formats` requires opening whatever can
                // be read rather than refusing the publication, and owning the
                // reader is what makes that possible (ADR-0008). The scan is
                // linear, which is inherent: recovery exists because there is no
                // index to seek with.
                try {
                    ZipReader.recovering(source)
                } catch (_: ZipException) {
                    throw ComicArchiveException.Unreadable()
                }
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
                //
                // In a recovered archive a zero *uncompressed* size means unknown
                // rather than empty — a local header with a data descriptor
                // declares none — so what matters there is whether bytes survived.
                val hasBytes = if (reader.isRecovered) {
                    entry.compressedSize > 0
                } else {
                    entry.uncompressedSize > 0
                }
                if (!hasBytes) {
                    skipped++
                    continue
                }
                // A recovered entry's uncompressed size is often unknown, so the
                // compressed size stands in. It is a lower bound on the page, which
                // beats zero for laying out a placeholder.
                val byteCount = if (entry.uncompressedSize > 0) {
                    entry.uncompressedSize
                } else {
                    entry.compressedSize
                }
                candidates += PageEntry(entry.path, byteCount)
                index[entry.path] = entry
            }

            return ZipComicArchive(
                source = source,
                reader = reader,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                comicInfoData = comicInfo?.let { reader.data(it) },
                pathToEntry = index,
                isRecovered = reader.isRecovered,
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

    /** The archive's parsed metadata, when it carries any. */
    val comicInfo: ComicInfo? by lazy { comicInfoData?.let(ComicInfo::parse) }

    override val coverPage: PageEntry?
        get() = CoverSelection.cover(pages, comicInfo?.coverPageIndex)

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

/**
 * A CBR.
 *
 * Indexes on headers alone: [RarReader] parses names, sizes and flags without a
 * decoder, so a remote CBR is catalogued without downloading it. Reading a
 * *compressed* page needs [RarDecoder], which is the only place libarchive is used
 * and the only part that needs a local file.
 *
 * That split is why this type takes an optional [File]. Given one, every page is
 * readable. Without one — a remote source not yet downloaded — stored pages read
 * and compressed pages count as skipped, which is what `publication-formats` means
 * by opening what can be read and reporting what was not.
 */
class RarComicArchive private constructor(
    private val source: RandomAccessSource,
    private val reader: RarReader,
    override val pages: List<PageEntry>,
    override val skippedPageCount: Int,
    private val pathToEntry: Map<String, RarEntry>,
    /** Where the archive lives on disk, when it does. */
    private val file: File?,
) : ComicArchiveReading {

    val generation: RarGeneration get() = reader.generation

    /**
     * Whether pages can be read out of order from a remote source.
     *
     * False for a solid archive, which has to be decompressed from the start.
     * `Streaming capability per format` requires flagging that before the user
     * taps a remote publication, rather than discovering it mid-read.
     */
    val isStreamable: Boolean get() = !reader.isSolid

    companion object {
        suspend fun open(source: RandomAccessSource, file: File? = null): RarComicArchive {
            val reader = try {
                RarReader.open(source)
            } catch (_: RarException.NotRar) {
                throw ComicArchiveException.UnrecognisedContainer()
            } catch (_: RarException) {
                throw ComicArchiveException.Unreadable()
            }

            if (reader.isEncrypted) throw ComicArchiveException.PasswordProtected()
            // Checked before the page list is built. For a solid RAR4 the first
            // entry reads fine and everything after it does not, so surfacing a
            // one-page comic here would be a lie. A solid RAR5 is readable once
            // local, so it passes — `isSolid` is what marks it non-streamable,
            // separately.
            if (!reader.isReadableWhenLocal) throw ComicArchiveException.SolidArchive()
            // No entries at all means the headers did not parse — a truncated or
            // damaged file, not an archive that happens to hold no images. The
            // ZIP path draws the same line: `no-pages.cbz` has entries and zero
            // pages.
            if (reader.entries.isEmpty()) throw ComicArchiveException.Unreadable()

            val candidates = mutableListOf<PageEntry>()
            val index = mutableMapOf<String, RarEntry>()
            var skipped = 0

            // A compressed entry is readable only with a local file to hand to
            // libarchive, and only if the native library is actually there.
            val canDecode = file != null && RarDecoder.isAvailable
            for (entry in reader.entries) {
                if (!PageOrdering.isPage(entry.path)) continue
                if ((!entry.isStored && !canDecode) || entry.size == 0L) {
                    skipped++
                    continue
                }
                candidates += PageEntry(entry.path, entry.size)
                index[entry.path] = entry
            }

            if (candidates.isEmpty() && skipped > 0) {
                // Pages exist but none can be read. That is a decoder gap, not a
                // damaged file, so it is named as the container it is.
                throw ComicArchiveException.UnsupportedContainer(FormatSniffer.Container.RAR)
            }

            return RarComicArchive(
                source = source,
                reader = reader,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                pathToEntry = index,
                file = file,
            )
        }
    }

    override suspend fun data(page: PageEntry): ByteArray {
        val entry = pathToEntry[page.path] ?: throw ComicArchiveException.Unreadable()
        if (entry.isStored) return reader.data(entry)
        val file = file ?: throw ComicArchiveException.UnsupportedContainer(
            FormatSniffer.Container.RAR,
        )
        return RarDecoder.data(file, entry.path)
    }

    /**
     * Every listed page's bytes in one pass over the archive.
     *
     * For a solid archive this is the only affordable shape: reading page 30 there
     * means decompressing 1 to 29, so asking page by page would be quadratic. The
     * indexer wants this anyway — it needs a cover and a spread check, not one
     * page.
     */
    fun allPageData(): Map<String, ByteArray> {
        val file = file ?: return emptyMap()
        if (!RarDecoder.isAvailable) return emptyMap()
        return RarDecoder.data(file, pages.map { it.path })
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
            FormatSniffer.Container.RAR -> RarComicArchive.open(source)
            // `publication-formats` requires a *named* refusal, never a generic
            // parse failure — `Container.displayName` is what carries the name.
            // 7-Zip is out of scope, and PDF has its own reader rather than an
            // archive one.
            FormatSniffer.Container.SEVEN_ZIP,
            FormatSniffer.Container.PDF,
            -> throw ComicArchiveException.UnsupportedContainer(container)
            null -> throw ComicArchiveException.UnrecognisedContainer()
        }
    }

    /**
     * Convenience for a local path — the only source type that exists today.
     *
     * A directory is routed to [ImageFolderArchive]: `publication-formats` lists a
     * plain folder of ordered images as a publication, and from the caller's side
     * opening one is the same action as opening a file.
     */
    /**
     * Convenience for a document the user picked through the Storage Access
     * Framework.
     *
     * Same decisions as [open] for a `File`: a folder of images is a publication,
     * and a RAR is handed a path so libarchive can decompress it — here
     * `/proc/self/fd/N`, which is the only path a content `Uri` has.
     */
    suspend fun open(resolver: ContentResolver, uri: Uri): ComicArchiveReading {
        if (SafTree.isDirectory(resolver, uri)) return DocumentFolderArchive.open(resolver, uri)
        val source = UriSource(resolver, uri)
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)
        return if (FormatSniffer.container(probe) == FormatSniffer.Container.RAR) {
            RarComicArchive.open(source, File(source.descriptorPath))
        } else {
            open(source)
        }
    }

    suspend fun open(file: File): ComicArchiveReading {
        if (file.isDirectory) return ImageFolderArchive.open(file)
        val source = FileSource(file)
        // A local RAR gets its file, which is what lets libarchive decompress a
        // page. Every other container reads through the source alone.
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)
        return if (FormatSniffer.container(probe) == FormatSniffer.Container.RAR) {
            RarComicArchive.open(source, file)
        } else {
            open(source)
        }
    }
}
