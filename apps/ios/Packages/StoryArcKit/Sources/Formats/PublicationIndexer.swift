public import Foundation

public import StoryArcCore

/// Turns a file into a `Publication`.
///
/// The seam between the format layer and the library. Everything below it knows
/// about containers; everything above it knows about books. `local-library`
/// requires a folder scan to "identify supported publications, extract covers and
/// metadata", and this is the per-file half of that.
///
/// Metadata has a precedence, and it is the whole point of the type. Embedded
/// metadata beats a guess from the filename, and both record where they came from
/// so an authoritative source can replace them later without raising a conflict
/// the app invented (`publication-formats`).
public enum PublicationIndexer {
    /// What went wrong, in terms the library can show without inventing a reason.
    public enum IndexError: Error, Equatable {
        /// A container StoryArc recognises and does not read. Carries the name so
        /// the message can say "7-Zip" rather than "could not open file".
        case unsupported(format: String)
        /// Recognised, supported, and this particular file cannot be read.
        case unreadable(reason: String)
    }

    /// Indexes one local publication.
    ///
    /// Opens the container, so it costs one read of the index and one of the cover
    /// — not of the whole file. A CBR is catalogued from its headers with nothing
    /// decompressed at all.
    /// - Parameter seriesHint: the name of the folder the file sits in, when that
    ///   folder is a subfolder of a picked library rather than the library itself.
    ///   `local-library` presents such a subfolder "as a series whose name is the
    ///   folder name", and this is the metadata half of that: a hint used only
    ///   where nothing better exists. Embedded metadata and the filename both beat
    ///   it, because both are statements about *this* publication and a folder name
    ///   is a statement about its neighbours.
    /// - Parameter catalogueSeries: the series a server that keeps the catalogue reported.
    ///   It beats the filename, which for a downloaded or cached publication is often an
    ///   identifier rather than a name.
    public static func index(
        fileAt url: URL,
        seriesHint: String? = nil,
        catalogueSeries: String? = nil
    ) async throws -> Publication {
        let filename = url.lastPathComponent
        let fallback = FilenameMetadata(
            filename: filename,
            seriesHint: seriesHint,
            catalogued: catalogueSeries
        )

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { throw IndexError.unreadable(reason: "the file is not there") }

        if isDirectory.boolValue {
            let folder = try ImageFolderArchive(directory: url)
            return comic(
                folder,
                format: .imageFolder,
                // No file, so no digest. A folder of images keys on its path alone.
                identity: identity(forPath: url.path, digest: nil),
                filename: url.lastPathComponent,
                fallback: FilenameMetadata(filename: url.lastPathComponent)
            )
        }

        let source = try FileSource(url: url)
        // Taken from the handle the sniff below is about to use, so both reads land on
        // pages this index is touching anyway. See `contentDigest(of:)`.
        let found = identity(forPath: url.path, digest: try? await contentDigest(of: source))
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)
        let container = FormatSniffer.container(of: probe)

        switch container {
        case .pdf:
            return try pdf(at: url, identity: found, filename: filename, fallback: fallback)
        case .zip:
            // An EPUB is a ZIP too, and only its contents tell the two apart.
            if let epub = try? await EpubReader(source: source) {
                return await book(
                    epub, at: url, identity: found, filename: filename, fallback: fallback
                )
            }
            return try await comicArchive(
                url: url, identity: found, format: .cbz, filename: filename, fallback: fallback
            )
        case .tar:
            return try await comicArchive(
                url: url, identity: found, format: .cbt, filename: filename, fallback: fallback
            )
        case .rar:
            return try await comicArchive(
                url: url, identity: found, format: .cbr, filename: filename, fallback: fallback
            )
        case .sevenZip:
            throw IndexError.unsupported(format: PublicationFormat.cb7.displayName)
        case nil:
            throw IndexError.unreadable(reason: "the format was not recognised")
        }
    }

    /// Indexes a publication that is not a local file.
    ///
    /// Everything the file-based path does, over a `RandomAccessSource` instead — which is
    /// what ADR-0008 put that interface there for. A share supplies one, so a comic on a NAS
    /// is catalogued from its headers rather than fetched.
    ///
    /// - Parameter decoderPath: a local copy, for the two decoders that cannot take a
    ///   source. PDFKit wants a file and libarchive wants a path; without one, those
    ///   formats are catalogued as records with their pages marked refused rather than
    ///   failing outright — the same honest degradation the file path already gives a
    ///   solid archive.
    public static func index(
        source: any RandomAccessSource,
        name: String,
        identity: PublicationIdentity,
        decoderPath: URL? = nil,
        seriesHint: String? = nil
    ) async throws -> Publication {
        let fallback = FilenameMetadata(filename: name, seriesHint: seriesHint)
        // The caller's identity says *where* this came from; the digest says *what* it
        // is. Recorded together, which is what ADR-0006 asks for whenever both are
        // known — and here both are, because the source is already open. A caller that
        // supplied a digest of its own keeps it.
        let found = identity.recordingDigest(try? await contentDigest(of: source))
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)

        switch FormatSniffer.container(of: probe) {
        case .pdf:
            guard let decoderPath else { return record(.pdf, found, name, fallback) }
            return try pdf(at: decoderPath, identity: found, filename: name, fallback: fallback)

        case .zip:
            // An EPUB is a ZIP too, and only its contents tell the two apart.
            if let epub = try? await EpubReader(source: source) {
                // The EPUB reader wants a file of its own, so a remote one is a record
                // until it has been fetched. Its metadata is still read from the share.
                guard let decoderPath else { return record(.epub, found, name, fallback) }
                return await book(
                    epub, at: decoderPath, identity: found, filename: name, fallback: fallback
                )
            }
            return comic(
                try await ComicArchiveOpener.open(source: source),
                format: .cbz,
                identity: found,
                filename: name,
                fallback: fallback
            )

        case .tar:
            return comic(
                try await TarComicArchive(source: source),
                format: .cbt,
                identity: found,
                filename: name,
                fallback: fallback
            )

        case .rar:
            guard let decoderPath else { return record(.cbr, found, name, fallback) }
            return try await comicArchive(
                url: decoderPath, identity: found, format: .cbr, filename: name,
                fallback: fallback
            )

        case .sevenZip:
            throw IndexError.unsupported(format: PublicationFormat.cb7.displayName)

        case nil:
            throw IndexError.unreadable(reason: "the format was not recognised")
        }
    }

    /// A publication that exists but whose pages cannot be reached from here.
    ///
    /// The library should list it and say why, not silently drop it — the same answer a
    /// solid archive already gets.
    private static func record(
        _ format: PublicationFormat,
        _ identity: PublicationIdentity,
        _ filename: String,
        _ fallback: FilenameMetadata
    ) -> Publication {
        Publication(
            identity: identity,
            format: format,
            displayTitle: title(from: nil, fallback: fallback, filename: filename),
            series: fallback.series,
            number: fallback.number,
            volume: fallback.volume,
            year: fallback.year,
            origin: .inferred,
            streaming: .refused
        )
    }

    // MARK: - Per-container

    private static func comicArchive(
        url: URL,
        identity: PublicationIdentity,
        format: PublicationFormat,
        filename: String,
        fallback: FilenameMetadata
    ) async throws -> Publication {
        let archive: any ComicArchiveReading
        do {
            archive = try await ComicArchiveOpener.open(fileAt: url)
        } catch ComicArchiveError.solidArchive {
            // Readable as a *record* even though it cannot be opened: the library
            // should list it and say why, not silently drop it.
            return Publication(
                identity: identity,
                format: format,
                displayTitle: title(from: nil, fallback: fallback, filename: filename),
                series: fallback.series,
                number: fallback.number,
                volume: fallback.volume,
                year: fallback.year,
                origin: .inferred,
                streaming: .refused
            )
        } catch ComicArchiveError.passwordProtected {
            throw IndexError.unreadable(reason: "the archive is password protected")
        } catch let ComicArchiveError.unsupportedContainer(container) {
            throw IndexError.unsupported(format: container.displayName)
        } catch {
            throw IndexError.unreadable(reason: "the archive could not be read")
        }
        return comic(
            archive,
            format: format,
            identity: identity,
            filename: filename,
            fallback: fallback
        )
    }

    private static func comic(
        _ archive: any ComicArchiveReading,
        format: PublicationFormat,
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata
    ) -> Publication {
        let info = (archive as? ZipComicArchive)?.comicInfo
            ?? (archive as? TarComicArchive)?.comicInfo
            ?? (archive as? ImageFolderArchive)?.comicInfo

        // Embedded metadata beats a filename guess, field by field rather than
        // wholesale: a ComicInfo with only a series should not discard a year the
        // filename knows.
        let series = info?.series ?? fallback.series
        let number = info?.number ?? fallback.number

        return Publication(
            identity: identity,
            format: format,
            displayTitle: title(from: info, fallback: fallback, filename: filename),
            series: series,
            number: number,
            volume: info?.volume ?? fallback.volume,
            authors: info?.writers ?? [],
            publisher: info?.publisher,
            year: info?.year ?? fallback.year,
            language: info?.language,
            summary: info?.summary,
            genres: info?.genres ?? [],
            tags: info?.tags ?? [],
            // Inferred unless *something* came out of the file itself. The flag
            // describes the record, and one embedded field makes the record
            // embedded — a later authoritative source replaces the whole thing.
            origin: info == nil ? .inferred : .embedded,
            pageCount: archive.pages.count,
            skippedPageCount: archive.skippedPageCount,
            coverPath: archive.coverPage?.path,
            readingDirection: info?.readingDirection ?? .leftToRight,
            streaming: streaming(of: archive),
            // An unpacked folder is not one file, so nothing outside can weigh it.
            // What it occupies is what its pages add up to, which is the same
            // question a packed archive's own length answers — and the pages have
            // just been walked, so asking costs nothing. Every other format is
            // weighed by the scan that found it.
            fileSize: format == .imageFolder
                ? archive.pages.reduce(0) { $0 + Int64($1.byteCount ?? 0) }
                : nil
        )
    }

    /// `async` for one reason: a publication that declares no cover has one resolved
    /// from its first spine item, which means reading that item out of the container.
    /// See ``EpubSpineCover``.
    private static func book(
        _ epub: EpubReader,
        at url: URL,
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata
    ) async -> Publication {
        let metadata = epub.metadata
        return Publication(
            identity: identity,
            format: .epub,
            displayTitle: metadata.title ?? fallback.series ?? filename,
            // The series the file declares, not its own title. This used to be
            // `metadata.title`, which made every book a series of one named after itself —
            // and `reading-themes` scopes a theme to the series, so two volumes of one work
            // could not share a setting. A book that declares no series still gets its own
            // shelf, because `ShelfMemory` falls back to the publication's identity.
            series: metadata.series ?? fallback.series,
            number: metadata.seriesIndex ?? fallback.number,
            volume: fallback.volume,
            authors: metadata.author.map { [$0] } ?? [],
            publisher: metadata.publisher,
            year: fallback.year,
            language: metadata.language,
            summary: metadata.description,
            origin: metadata.title == nil ? .inferred : .embedded,
            // The spine, not a page count: an EPUB's pages depend on the type size
            // the reader is set to, so there is no number to record here.
            pageCount: epub.spine.count,
            // `publication-formats`: the declared cover, "otherwise the first page of
            // the spine is rendered as the cover".
            coverPath: await epub.coverOrSpineHref(),
            readingDirection: ReadingDirection.inferred(
                declared: nil, languageCode: metadata.language
            ),
            isFixedLayout: epub.isFixedLayout
        )
    }

    private static func pdf(
        at url: URL, identity: PublicationIdentity, filename: String, fallback: FilenameMetadata
    ) throws -> Publication {
        let reader: PdfDocumentReader
        do {
            reader = try PdfDocumentReader(url: url)
        } catch {
            throw IndexError.unreadable(reason: "the PDF could not be opened")
        }
        return Publication(
            identity: identity,
            format: .pdf,
            displayTitle: fallback.series ?? filename,
            series: fallback.series,
            number: fallback.number,
            volume: fallback.volume,
            year: fallback.year,
            origin: .inferred,
            pageCount: reader.pageCount,
            // A PDF page is rendered rather than extracted, so there is no path to
            // point at. The cover is page one, produced on demand.
            coverPath: nil
        )
    }

    // MARK: - Shared rules

    /// Streaming capability, from what the container itself reported.
    private static func streaming(of archive: any ComicArchiveReading) -> StreamingCapability {
        guard let rar = archive as? RarComicArchive else { return .streams }
        // A solid RAR5 reads once local; a solid RAR4 never opens at all and is
        // refused before it reaches here.
        return rar.isStreamable ? .streams : .downloadOnly
    }

    /// What to show in a list.
    ///
    /// A title if the file states one, then series and number assembled, then the
    /// filename — which is always *something*, and a library row with no text at
    /// all is worse than one showing a filename.
    private static func title(
        from info: ComicInfo?, fallback: FilenameMetadata, filename: String
    ) -> String {
        if let title = info?.title, !title.isEmpty { return title }
        let series = info?.series ?? fallback.series
        let number = info?.number ?? fallback.number
        if let series {
            return number.map { "\(series) #\($0)" } ?? series
        }
        return filename
    }
}
