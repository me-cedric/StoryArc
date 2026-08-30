package app.storyarc.core.format

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.StreamingCapability
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/** What went wrong, in terms the library can show without inventing a reason. */
sealed class IndexException(message: String) : Exception(message) {
    /**
     * A container StoryArc recognises and does not read. Carries the name so the
     * message can say "7-Zip" rather than "could not open file".
     */
    class Unsupported(val format: String) : IndexException("unsupported format: $format")

    /** Recognised, supported, and this particular file cannot be read. */
    class Unreadable(val reason: String) : IndexException(reason)
}

/**
 * Turns a file into a [Publication].
 *
 * The seam between the format layer and the library. Everything below it knows
 * about containers; everything above it knows about books. `local-library`
 * requires a folder scan to "identify supported publications, extract covers and
 * metadata", and this is the per-file half of that.
 *
 * Metadata has a precedence, and it is the whole point of the type. Embedded
 * metadata beats a guess from the filename, and both record where they came from
 * so an authoritative source can replace them later without raising a conflict the
 * app invented (`publication-formats`).
 */
object PublicationIndexer {

    /**
     * Indexes one local publication.
     *
     * Opens the container, so it costs one read of the index and one of the cover —
     * not of the whole file. A CBR is catalogued from its headers with nothing
     * decompressed at all.
     */
    /**
     * Indexes a publication reached through a [RandomAccessSource].
     *
     * The Storage Access Framework hands back a `Uri` rather than a path, so a
     * user-picked folder cannot be indexed through the `File` overload. Everything
     * below already takes a source (ADR-0008); this is where that pays off.
     *
     * [decoderPath] is the one thing a source cannot provide: libarchive and
     * `PdfRenderer` want a path. A [UriSource] can offer `/proc/self/fd/N`, and
     * without one a compressed CBR indexes with its pages marked skipped rather
     * than failing — the same honest degradation as a remote archive.
     */
    suspend fun index(
        source: RandomAccessSource,
        name: String,
        identity: PublicationIdentity,
        decoderPath: File? = null,
        seriesHint: String? = null,
    ): Publication {
        val fallback = FilenameMetadata.of(name, seriesHint)
        // A content `Uri` has no path, and libarchive wants one. `/proc/self/fd/N`
        // is a real path to the same open file, so a compressed CBR on a provider
        // decodes without being copied anywhere first.
        val decoder = decoderPath ?: (source as? UriSource)?.let { File(it.descriptorPath) }
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)

        return when (FormatSniffer.container(probe)) {
            // PdfRenderer needs a real descriptor, which a caller supplies as a
            // path. Without one the row still exists, with no page count — the
            // library can show it and the reader can open it from a local copy.
            FormatSniffer.Container.PDF -> pdf(identity, name, fallback)

            FormatSniffer.Container.ZIP -> {
                val epub = runCatching { EpubReader.open(source) }.getOrNull()
                if (epub != null) {
                    book(epub, identity, name, fallback)
                } else {
                    comicFromSource(source, PublicationFormat.CBZ, identity, name, fallback, decoder)
                }
            }

            FormatSniffer.Container.TAR ->
                comicFromSource(source, PublicationFormat.CBT, identity, name, fallback, decoder)

            FormatSniffer.Container.RAR ->
                comicFromSource(source, PublicationFormat.CBR, identity, name, fallback, decoder)

            FormatSniffer.Container.SEVEN_ZIP ->
                throw IndexException.Unsupported(PublicationFormat.CB7.displayName)

            null -> throw IndexException.Unreadable("the format was not recognised")
        }
    }

    private suspend fun comicFromSource(
        source: RandomAccessSource,
        format: PublicationFormat,
        identity: PublicationIdentity,
        name: String,
        fallback: FilenameMetadata,
        decoderPath: File?,
    ): Publication {
        val archive = try {
            when (format) {
                PublicationFormat.CBR -> RarComicArchive.open(source, decoderPath)
                PublicationFormat.CBT -> TarComicArchive.open(source)
                else -> ZipComicArchive.open(source)
            }
        } catch (_: ComicArchiveException.SolidArchive) {
            return Publication(
                identity = identity,
                format = format,
                displayTitle = title(null, fallback, name),
                series = fallback.series,
                number = fallback.number,
                volume = fallback.volume,
                year = fallback.year,
                origin = MetadataOrigin.INFERRED,
                streaming = StreamingCapability.REFUSED,
            )
        } catch (_: ComicArchiveException.PasswordProtected) {
            throw IndexException.Unreadable("the archive is password protected")
        } catch (cause: ComicArchiveException.UnsupportedContainer) {
            throw IndexException.Unsupported(cause.container.displayName)
        } catch (_: ComicArchiveException) {
            throw IndexException.Unreadable("the archive could not be read")
        }
        return comic(archive, format, identity, name, fallback)
    }

    /**
     * Indexes an already-open archive.
     *
     * The unpacked-folder case, where there is no single file to sniff. Both the
     * `File` and the tree walk arrive here for a directory of images.
     */
    fun index(
        archive: ComicArchiveReading,
        identity: PublicationIdentity,
        name: String,
        seriesHint: String? = null,
    ): Publication = comic(
        archive,
        PublicationFormat.IMAGE_FOLDER,
        identity,
        name,
        FilenameMetadata.of(name, seriesHint),
    )

    /**
     * @param seriesHint the name of the folder the file sits in, when that folder
     *   is a subfolder of a picked library rather than the library itself.
     *   `local-library` presents such a subfolder "as a series whose name is the
     *   folder name", and this is the metadata half of that: a hint used only where
     *   nothing better exists. Embedded metadata and the filename both beat it,
     *   because both are statements about *this* publication and a folder name is a
     *   statement about its neighbours.
     */
    suspend fun index(
        file: File,
        seriesHint: String? = null,
        catalogueSeries: String? = null,
    ): Publication {
        val filename = file.name
        val fallback = FilenameMetadata.of(filename, seriesHint, catalogueSeries)

        if (file.isDirectory) {
            return comic(
                ImageFolderArchive.open(file),
                PublicationFormat.IMAGE_FOLDER,
                identityFor(file),
                filename,
                fallback,
            )
        }
        if (!file.isFile) throw IndexException.Unreadable("the file is not there")

        val source = FileSource(file)
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)
        return when (FormatSniffer.container(probe)) {
            FormatSniffer.Container.PDF -> pdf(identityFor(file), filename, fallback)

            FormatSniffer.Container.ZIP -> {
                // An EPUB is a ZIP too, and only its contents tell the two apart.
                val epub = runCatching { EpubReader.open(FileSource(file)) }.getOrNull()
                if (epub != null) {
                    book(epub, identityFor(file), filename, fallback)
                } else {
                    comicArchive(file, PublicationFormat.CBZ, filename, fallback)
                }
            }

            FormatSniffer.Container.TAR ->
                comicArchive(file, PublicationFormat.CBT, filename, fallback)

            FormatSniffer.Container.RAR ->
                comicArchive(file, PublicationFormat.CBR, filename, fallback)

            FormatSniffer.Container.SEVEN_ZIP ->
                throw IndexException.Unsupported(PublicationFormat.CB7.displayName)

            null -> throw IndexException.Unreadable("the format was not recognised")
        }
    }

    // Per-container.

    private suspend fun comicArchive(
        file: File,
        format: PublicationFormat,
        filename: String,
        fallback: FilenameMetadata,
    ): Publication {
        val archive = try {
            ComicArchiveOpener.open(file)
        } catch (_: ComicArchiveException.SolidArchive) {
            // Readable as a *record* even though it cannot be opened: the library
            // should list it and say why, not silently drop it.
            return Publication(
                identity = identityFor(file),
                format = format,
                displayTitle = title(null, fallback, filename),
                series = fallback.series,
                number = fallback.number,
                volume = fallback.volume,
                year = fallback.year,
                origin = MetadataOrigin.INFERRED,
                streaming = StreamingCapability.REFUSED,
            )
        } catch (_: ComicArchiveException.PasswordProtected) {
            throw IndexException.Unreadable("the archive is password protected")
        } catch (cause: ComicArchiveException.UnsupportedContainer) {
            throw IndexException.Unsupported(cause.container.displayName)
        } catch (_: ComicArchiveException) {
            throw IndexException.Unreadable("the archive could not be read")
        }
        return comic(archive, format, identityFor(file), filename, fallback)
    }

    private fun comic(
        archive: ComicArchiveReading,
        format: PublicationFormat,
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata,
    ): Publication {
        val info = when (archive) {
            is ZipComicArchive -> archive.comicInfo
            is TarComicArchive -> archive.comicInfo
            is ImageFolderArchive -> archive.comicInfo
            is DocumentFolderArchive -> archive.comicInfo
            else -> null
        }

        return Publication(
            identity = identity,
            format = format,
            displayTitle = title(info, fallback, filename),
            // Embedded metadata beats a filename guess, field by field rather than
            // wholesale: a ComicInfo with only a series should not discard a year
            // the filename knows.
            series = info?.series ?: fallback.series,
            number = info?.number ?: fallback.number,
            volume = info?.volume ?: fallback.volume,
            authors = info?.writers ?: emptyList(),
            publisher = info?.publisher,
            year = info?.year ?: fallback.year,
            language = info?.language,
            summary = info?.summary,
            genres = info?.genres.orEmpty(),
            tags = info?.tags.orEmpty(),
            // Inferred unless *something* came out of the file itself. The flag
            // describes the record, and one embedded field makes the record
            // embedded — a later authoritative source replaces the whole thing.
            origin = if (info == null) MetadataOrigin.INFERRED else MetadataOrigin.EMBEDDED,
            pageCount = archive.pages.size,
            skippedPageCount = archive.skippedPageCount,
            coverPath = archive.coverPage?.path,
            readingDirection = info?.readingDirection ?: ReadingDirection.LEFT_TO_RIGHT,
            streaming = streamingOf(archive),
            // An unpacked folder is not one file, so nothing outside can weigh it.
            // What it occupies is what its pages add up to, which is the same
            // question a packed archive's own length answers — and the pages have
            // just been walked, so asking costs nothing. Every other format is
            // weighed by the scan that found it.
            fileSize = if (format == PublicationFormat.IMAGE_FOLDER) {
                archive.pages.sumOf { it.byteCount ?: 0L }
            } else {
                null
            },
        )
    }

    private fun book(
        epub: EpubReader,
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata,
    ): Publication = Publication(
        identity = identity,
        format = PublicationFormat.EPUB,
        displayTitle = epub.metadata.title ?: fallback.series ?: filename,
        // The series the file declares, not its own title. This used to be
        // `metadata.title`, which made every book a series of one named after itself -- and
        // `reading-themes` scopes a theme to the series, so two volumes of one work could
        // not share a setting. A book that declares no series still gets its own shelf,
        // because `ShelfMemory` falls back to the publication's identity.
        series = epub.metadata.series ?: fallback.series,
        number = epub.metadata.seriesIndex ?: fallback.number,
        volume = fallback.volume,
        authors = epub.metadata.author?.let { listOf(it) } ?: emptyList(),
        publisher = epub.metadata.publisher,
        year = fallback.year,
        language = epub.metadata.language,
        summary = epub.metadata.description,
        origin = if (epub.metadata.title == null) MetadataOrigin.INFERRED else MetadataOrigin.EMBEDDED,
        // The spine, not a page count: an EPUB's pages depend on the type size the
        // reader is set to, so there is no number to record here.
        pageCount = epub.spine.size,
        coverPath = epub.coverHref,
        readingDirection = ReadingDirection.inferred(null, epub.metadata.language),
        isFixedLayout = epub.isFixedLayout,
    )

    /**
     * PDF is indexed without opening it.
     *
     * `PdfRenderer` is a framework class, so touching it here would make the
     * indexer untestable on a host JVM and would drag a device dependency into a
     * folder scan. Page count arrives when the reader opens the document; the
     * library needs a row, a title and a format, and it has all three.
     *
     * iOS reads the page count during indexing because PDFKit runs on the host.
     * That asymmetry is in the platforms, and the field is nullable for exactly
     * this reason.
     */
    private fun pdf(
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata,
    ): Publication =
        Publication(
            identity = identity,
            format = PublicationFormat.PDF,
            displayTitle = fallback.series ?: filename,
            series = fallback.series,
            number = fallback.number,
            volume = fallback.volume,
            year = fallback.year,
            origin = MetadataOrigin.INFERRED,
            pageCount = null,
            // A PDF page is rendered rather than extracted, so there is no path to
            // point at. The cover is page one, produced on demand.
            coverPath = null,
        )

    // Shared rules.

    /** Streaming capability, from what the container itself reported. */
    private fun streamingOf(archive: ComicArchiveReading): StreamingCapability {
        val rar = archive as? RarComicArchive ?: return StreamingCapability.STREAMS
        // A solid RAR5 reads once local; a solid RAR4 never opens at all and is
        // refused before it reaches here.
        return if (rar.isStreamable) StreamingCapability.STREAMS else StreamingCapability.DOWNLOAD_ONLY
    }

    /**
     * What to show in a list.
     *
     * A title if the file states one, then series and number assembled, then the
     * filename — which is always *something*, and a library row with no text at all
     * is worse than one showing a filename.
     */
    private fun title(info: ComicInfo?, fallback: FilenameMetadata, filename: String): String {
        info?.title?.takeIf { it.isNotEmpty() }?.let { return it }
        val series = info?.series ?: fallback.series
        val number = info?.number ?: fallback.number
        if (series != null) return if (number != null) "$series #$number" else series
        return filename
    }

    /**
     * An identity keyed on the normalised path.
     *
     * ADR-0006 prefers a content digest, which survives renames and moves. That is
     * deliberately not done here: digesting a 400 MB archive during a scan of 10,000
     * files would break `local-library`'s three-second requirement outright.
     *
     * ponytail: the digest belongs to a background pass that fills it in after the
     * first screen is on-screen, and [PublicationIdentity.matches] already merges
     * the two when it arrives. Until that pass exists, a moved file loses its place
     * — which is the honest cost and is recorded here rather than hidden.
     */
    fun identityFor(file: File): PublicationIdentity =
        PublicationIdentity(normalizedPath = file.absoluteFile.normalize().path)

    /**
     * A content digest for one publication.
     *
     * Not called during a scan — see [identityFor]. Offered so the background pass
     * that upgrades an identity has one implementation to use rather than inventing
     * its own, and so the two platforms hash the same bytes.
     *
     * Hashes the first and last 512 KB plus the file length, not the whole file: a
     * comic that differs from another in neither its head, its tail, nor its size is
     * the same comic, and reading gigabytes to prove it is not worth the disk.
     */
    suspend fun contentDigest(file: File): String {
        val source = FileSource(file)
        val window = 512 * 1024
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(
            ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(source.length).array(),
        )
        digest.update(source.read(0, window))
        if (source.length > window) {
            digest.update(source.readTail(window).first)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
