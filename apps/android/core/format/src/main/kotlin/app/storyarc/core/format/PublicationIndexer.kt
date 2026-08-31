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

    /**
     * An audiobook locked by its store's content protection.
     *
     * Its own case, because `publication-formats` requires the refusal to be "distinct
     * from an unsupported container, because the format itself is supported and this
     * particular file is locked". Folded into [Unsupported] the app would say MPEG-4 is a
     * format it does not read — false, and it sends the reader off to convert a file that
     * needs no converting.
     *
     * It carries no key, no account and no activation code, and it never will: StoryArc
     * does not implement, circumvent or advise on removing a content protection.
     */
    class ContentProtected(val container: String) :
        IndexException("$container is protected by its store's content protection")
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
        // The caller's identity says *where* this came from; the digest says *what* it is.
        // Recorded together, which is what ADR-0006 asks for whenever both are known — and
        // here both are, because the source is already open. This is the whole of what a
        // folder picked through the Storage Access Framework gets: it is reached by `Uri`
        // and has no `File` to digest separately.
        @Suppress("NAME_SHADOWING")
        val identity = identity.recordingDigest(runCatching { contentDigest(source) }.getOrNull())
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)

        return when (val container = FormatSniffer.container(probe)) {
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

            // A player opens these, not a reader. This used to be a *named refusal*, and
            // the refusal was true while StoryArc could not play audio; it is not any more.
            FormatSniffer.Container.MP4,
            FormatSniffer.Container.MP3,
            FormatSniffer.Container.FLAC,
            FormatSniffer.Container.OGG,
            -> audiobook(container, identity, name, fallback)

            // Refused by *name*, and separately from an unsupported container, because the
            // format is supported and this particular file is locked.
            FormatSniffer.Container.PROTECTED_AUDIOBOOK ->
                throw IndexException.ContentProtected(container.displayName)

            null -> throw IndexException.Unreadable("the format was not recognised")
        }
    }

    /**
     * A single audio file, as a one-part audiobook.
     *
     * **No chapter marks are read here, and that is the design rather than a gap.**
     * Reading them costs an extractor per file, and a library of five hundred audiobooks
     * would pay it on every scan to fill in a list nobody has opened. The player reads the
     * container's own markers when it opens the book (`design.md`); indexing records what
     * the file *is*.
     *
     * So the part count is 1 — the whole of the file standing in for a chapter, which is
     * exactly what `publication-formats` asks of an unchaptered audiobook: "its parts —
     * the files, or the whole of a single file — stand in for chapters".
     */
    private fun audiobook(
        container: FormatSniffer.Container,
        identity: PublicationIdentity,
        name: String,
        fallback: FilenameMetadata,
    ): Publication = Publication(
        identity = identity,
        format = audioFormat(container),
        displayTitle = title(null, fallback, name),
        series = fallback.series,
        number = fallback.number,
        volume = fallback.volume,
        year = fallback.year,
        origin = MetadataOrigin.INFERRED,
        pageCount = 1,
    )

    /** The domain format an audio container is. Total, so a new container is a compile error. */
    private fun audioFormat(container: FormatSniffer.Container): PublicationFormat =
        when (container) {
            FormatSniffer.Container.MP4 -> PublicationFormat.M4B
            FormatSniffer.Container.MP3 -> PublicationFormat.MP3
            FormatSniffer.Container.FLAC -> PublicationFormat.FLAC
            FormatSniffer.Container.OGG -> PublicationFormat.OGG
            FormatSniffer.Container.PROTECTED_AUDIOBOOK,
            FormatSniffer.Container.ZIP,
            FormatSniffer.Container.RAR,
            FormatSniffer.Container.SEVEN_ZIP,
            FormatSniffer.Container.PDF,
            FormatSniffer.Container.TAR,
            -> error("$container is not an audio container")
        }

    /**
     * A folder of ordered audio files, as one audiobook.
     *
     * The part count is the folder's own, and the parts that hold nothing are counted
     * apart — `publication-formats` asks a damaged audiobook to play "what it can" and
     * state "how much it could not", by the same rule that opens a comic missing pages.
     */
    private fun audiobookFolder(
        folder: AudiobookFolder,
        identity: PublicationIdentity,
        name: String,
        fallback: FilenameMetadata,
    ): Publication = Publication(
        identity = identity,
        format = PublicationFormat.AUDIO_FOLDER,
        displayTitle = title(null, fallback, name),
        series = fallback.series,
        number = fallback.number,
        volume = fallback.volume,
        year = fallback.year,
        origin = MetadataOrigin.INFERRED,
        pageCount = folder.parts.size,
        skippedPageCount = folder.skippedPartCount,
    )

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
            // A folder is asked which kind it is rather than assumed to be a comic.
            // `publication-formats` lists a folder of ordered audio as a publication too,
            // and gives a majority rule for one holding both. `FolderKind` owns that rule;
            // this is the one place the answer changes what gets built.
            //
            // The names are read once and handed over, so the walk that decides and the
            // walk that reads are not two walks disagreeing about what is in the folder.
            val kind = FolderKind.of(file.walkTopDown().filter { it.isFile }.map { entry ->
                entry.relativeTo(file).invariantSeparatorsPath
            }.asIterable())

            if (kind == FolderKind.AUDIOBOOK) {
                return audiobookFolder(
                    AudiobookFolder.open(file),
                    // No file, so no digest. A folder keys on its path alone.
                    identityFor(file),
                    filename,
                    fallback,
                )
            }
            return comic(
                ImageFolderArchive.open(file),
                PublicationFormat.IMAGE_FOLDER,
                identityFor(file),
                filename,
                fallback,
            )
        }
        if (!file.isFile) throw IndexException.Unreadable("the file is not there")

        // Both reads come off the one handle the sniff below already needs, and it is
        // closed rather than left to the collector — see [contentDigest].
        val (identity, probe) = FileSource(file).use { source ->
            identityFor(file, runCatching { contentDigest(source) }.getOrNull()) to
                source.read(0, FormatSniffer.PROBE_LENGTH)
        }
        return when (val container = FormatSniffer.container(probe)) {
            FormatSniffer.Container.PDF -> pdf(identity, filename, fallback)

            FormatSniffer.Container.ZIP -> {
                // An EPUB is a ZIP too, and only its contents tell the two apart.
                val epub = runCatching { EpubReader.open(FileSource(file)) }.getOrNull()
                if (epub != null) {
                    book(epub, identity, filename, fallback)
                } else {
                    comicArchive(file, identity, PublicationFormat.CBZ, filename, fallback)
                }
            }

            FormatSniffer.Container.TAR ->
                comicArchive(file, identity, PublicationFormat.CBT, filename, fallback)

            FormatSniffer.Container.RAR ->
                comicArchive(file, identity, PublicationFormat.CBR, filename, fallback)

            FormatSniffer.Container.SEVEN_ZIP ->
                throw IndexException.Unsupported(PublicationFormat.CB7.displayName)

            // See the source overload. A player opens these; the refusal that used to
            // stand here was true only while there was no player.
            FormatSniffer.Container.MP4,
            FormatSniffer.Container.MP3,
            FormatSniffer.Container.FLAC,
            FormatSniffer.Container.OGG,
            -> audiobook(container, identity, filename, fallback)

            FormatSniffer.Container.PROTECTED_AUDIOBOOK ->
                throw IndexException.ContentProtected(container.displayName)

            null -> throw IndexException.Unreadable("the format was not recognised")
        }
    }

    // Per-container.

    private suspend fun comicArchive(
        file: File,
        identity: PublicationIdentity,
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
                identity = identity,
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
        return comic(archive, format, identity, filename, fallback)
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

    /**
     * `suspend` for one reason: a publication that declares no cover has one resolved
     * from its first spine item, which means reading that item out of the container.
     * See [EpubSpineCover].
     */
    private suspend fun book(
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
        // `publication-formats`: the declared cover, "otherwise the first page of the
        // spine is rendered as the cover".
        coverPath = epub.coverOrSpineHref(),
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
     * An identity carrying both what the publication *is* and where it was found.
     *
     * ADR-0006's rules 2 and 3 together. The path is what the app files the publication
     * under ([PublicationIdentity.stableId]); the digest is what recognises it again
     * after a rename or a move, because [PublicationIdentity.matches] and `ProgressStore`
     * both try the digest before the path. A `null` digest is the honest answer for
     * something that has no file of its own — a folder of images — and leaves the path as
     * the only key, which is what every publication had before the digest was computed at
     * all.
     */
    fun identityFor(file: File, digest: String? = null): PublicationIdentity =
        PublicationIdentity(
            contentDigest = digest,
            normalizedPath = file.absoluteFile.normalize().path,
        )

    /**
     * How many bytes at each end of a publication the digest reads.
     *
     * ADR-0006 writes the rule as "the file's size plus the first and last 64 KB". The
     * window here is larger, and is deliberately **not** being reduced to the number in
     * that sentence: the digest string is a bare hex SHA-256 with no scheme tag, so
     * changing what it is computed from turns every digest already written into a
     * stranger, and the records that carry one — a file this app was handed from outside
     * — have no path to fall back to. Eight times cheaper is not worth losing them. What
     * ADR-0006 actually decides is the *shape* — size, head, tail, no full read — and
     * that is unchanged.
     */
    private const val DIGEST_WINDOW = 512 * 1024

    /**
     * A content digest for one publication: what makes a moved file the same file.
     *
     * **SHA-256 over three things, in this order:** the source's length as eight
     * little-endian bytes, its first [DIGEST_WINDOW] bytes, and its last [DIGEST_WINDOW]
     * bytes — the tail omitted when the source is no longer than the window, because the
     * head already covered every byte there is.
     *
     * *Why not the whole file.* A comic is tens to hundreds of megabytes and this runs
     * for every publication a folder walk finds. Reading all of it would put gigabytes of
     * I/O in front of the first screen of covers, which `local-library` gives three
     * seconds.
     *
     * *Why not the name.* The name is the one thing a rename changes, and a rename losing
     * someone's place is the whole reason this exists.
     *
     * *Why the raw bytes and not the archive's contents.* Two entries beyond the central
     * directory would make this a parse, and AGENTS.md is blunt that the central
     * directory is a ZIP's only authority — a data descriptor leaves zeros in the local
     * headers, so a digest built from those would agree between two unrelated archives.
     * Hashing bytes takes no position on what the container says about itself:
     * `data-descriptor.cbz` and `truncated.cbz` digest exactly as readily as a well-formed
     * one, and a file too broken to index still gets an identity.
     *
     * *What it cannot tell apart.* Two files of the same length differing only in the
     * middle. For a comic that means an archive re-compressed at a different level to the
     * same byte count, which is not a thing that happens by accident — and the accepted
     * trade for reading a megabyte instead of four hundred. `PublicationIndexerTest`
     * asserts it rather than leaving it to be discovered.
     *
     * *Where the bytes come from.* A [RandomAccessSource], so the caller passes the handle
     * it already opened to sniff the format and read the central directory: the reads land
     * on pages the indexer has just touched, and nothing is opened twice. ADR-0008's
     * interface is what makes that possible, and it is the same reason this works over a
     * share without a full transfer.
     */
    suspend fun contentDigest(source: RandomAccessSource): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(
            ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(source.length).array(),
        )
        digest.update(source.read(0, DIGEST_WINDOW))
        if (source.length > DIGEST_WINDOW) {
            digest.update(source.readTail(DIGEST_WINDOW).first)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * The digest of a local file. See [contentDigest] for what is hashed.
     *
     * Closes the handle it opens. A scan of ten thousand files leaking one descriptor
     * each would exhaust the process limit long before it finished — the same reason
     * `LibraryScanner` closes its `UriSource`.
     */
    suspend fun contentDigest(file: File): String = FileSource(file).use { contentDigest(it) }
}
