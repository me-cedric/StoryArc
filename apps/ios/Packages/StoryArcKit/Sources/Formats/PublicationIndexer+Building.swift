public import Foundation

public import StoryArcCore

/// How ``PublicationIndexer`` turns an opened container into a `Publication`.
///
/// Split out of `PublicationIndexer.swift` when audio containers pushed that file
/// past the 400-line cap. The seam is a real one rather than a cut made to fit:
/// above it is *which* reader a file gets, which is the sniffing question; below it
/// is what a `Publication` is built out of once a reader is open, which is the
/// metadata-precedence question. They change for different reasons.
/// > These builders were `private` while they shared a file with their callers.
/// > Swift scopes `private` to the file, so the split makes them `internal` — the
/// > module, which is still narrower than the `package` the rest of StoryArcKit
/// > could see. Nothing outside `Formats` can reach them.
extension PublicationIndexer {
    /// A publication that exists but whose pages cannot be reached from here.
    ///
    /// The library should list it and say why, not silently drop it — the same answer a
    /// solid archive already gets.
    static func record(
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

    static func comicArchive(
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

    static func comic(
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
    static func book(
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

    static func pdf(
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
    static func streaming(of archive: any ComicArchiveReading) -> StreamingCapability {
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
    static func title(
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
    /// A ZIP over a source: an EPUB if its contents say so, a CBZ otherwise.
    ///
    /// Extracted from `index(source:…)` rather than inlined, because with audio
    /// containers added that function crossed the complexity cap — and this branch is
    /// the one part of it that asks a second question after the sniff.
    static func zipPublication(
        source: any RandomAccessSource,
        identity: PublicationIdentity,
        name: String,
        decoderPath: URL?,
        fallback: FilenameMetadata
    ) async throws -> Publication {
        // An EPUB is a ZIP too, and only its contents tell the two apart.
        if let epub = try? await EpubReader(source: source) {
            // The EPUB reader wants a file of its own, so a remote one is a record
            // until it has been fetched. Its metadata is still read from the share.
            guard let decoderPath else { return record(.epub, identity, name, fallback) }
            return await book(
                epub, at: decoderPath, identity: identity, filename: name, fallback: fallback
            )
        }
        return comic(
            try await ComicArchiveOpener.open(source: source),
            format: .cbz,
            identity: identity,
            filename: name,
            fallback: fallback
        )
    }

    /// A ZIP at a path: an EPUB if its contents say so, a CBZ otherwise.
    ///
    /// The file-based twin of the helper above. They differ in what they hand the
    /// comic path — a URL, which libarchive can take, against a source, which it
    /// cannot — so they are two functions rather than one with a flag.
    static func zipPublication(
        at url: URL,
        source: any RandomAccessSource,
        identity: PublicationIdentity,
        filename: String,
        fallback: FilenameMetadata
    ) async throws -> Publication {
        // An EPUB is a ZIP too, and only its contents tell the two apart.
        if let epub = try? await EpubReader(source: source) {
            return await book(
                epub, at: url, identity: identity, filename: filename, fallback: fallback
            )
        }
        return try await comicArchive(
            url: url, identity: identity, format: .cbz, filename: filename, fallback: fallback
        )
    }
}
