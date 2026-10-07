public import Foundation

/// A CBR.
///
/// Indexes on headers alone: `RarReader` parses names, sizes and flags without a
/// decoder, so a remote CBR is catalogued without downloading it. Reading a
/// *compressed* page needs `RarDecoder`, which is the only place libarchive is
/// used.
///
/// This type takes an optional URL. Given one, every page decodes from the file.
/// Without one — a remote source not yet downloaded — a stored page reads by
/// range, and a compressed page of a non-solid archive decodes from its own
/// ranged bytes (`RarReader.isolated(_:)`). Only a solid archive needs the whole
/// file: its compressed pages set ``isDownloadOnly`` rather than being dropped or
/// failing the whole archive, which is what `publication-formats` means by
/// cataloguing a publication without transferring it.
///
/// Split out of `ComicArchive.swift`, which had reached the 400-line cap this
/// project enforces.
public struct RarComicArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    public let generation: RarGeneration
    /// `ComicInfo.xml` contents when the archive carries one, read by range when it is
    /// stored and through `RarDecoder` when a local file exists and it is not.
    public let comicInfoData: Data?
    /// The archive's parsed metadata, when it carries any.
    public let comicInfo: ComicInfo?
    /// Whether pages can be read out of order from a remote source.
    ///
    /// False for a solid archive, which has to be decompressed from the start.
    /// `Streaming capability per format` requires flagging that before the user
    /// taps a remote publication, rather than discovering it mid-read.
    public let isStreamable: Bool
    /// True when at least one listed page is compressed in a solid archive and
    /// there is no local file yet to hand to `RarDecoder`.
    ///
    /// Set only in index-only mode — a remote CBR catalogued from its headers
    /// alone. `publication-formats`' streaming table marks such a publication
    /// download-only: the pages are real and counted, but none of the
    /// compressed ones can be read until the file arrives.
    public let isDownloadOnly: Bool

    private let reader: RarReader
    private let pathToEntry: [String: RarEntry]
    /// Where the archive lives on disk, when it does. `nil` means compressed
    /// entries cannot be decoded yet.
    private let fileURL: URL?

    public init(source: any RandomAccessSource, fileURL: URL? = nil) async throws {
        self.fileURL = fileURL
        do {
            self.reader = try await RarReader(source: source)
        } catch RarError.notRar {
            throw ComicArchiveError.unrecognisedContainer
        } catch {
            throw ComicArchiveError.unreadable
        }
        self.generation = reader.generation

        if reader.isEncrypted { throw ComicArchiveError.passwordProtected }
        // Checked before the page list is built. For a solid RAR4 the first entry
        // reads fine and everything after it does not, so surfacing a one-page
        // comic here would be a lie. A solid RAR5 is readable once local, so it
        // passes — `isSolid` is what marks it non-streamable, separately.
        if !reader.isReadableWhenLocal { throw ComicArchiveError.solidArchive }

        // No entries at all means the headers did not parse — a truncated or
        // damaged file, not an archive that happens to hold no images. The ZIP
        // path draws the same line: `no-pages.cbz` has entries and zero pages.
        if reader.entries.isEmpty { throw ComicArchiveError.unreadable }

        var candidates: [PageEntry] = []
        var skipped = 0
        var undecodable = 0
        var index: [String: RarEntry] = [:]
        let comicInfoEntry = reader.entries.first { $0.path.lowercased().hasSuffix("comicinfo.xml") }

        for entry in reader.entries where PageOrdering.isPage(path: entry.path) {
            // A zero-length entry never decodes to anything, local file or not.
            guard entry.size > 0 else {
                skipped += 1
                continue
            }
            // A compressed entry of a solid archive is readable only with a local
            // file to hand to libarchive. Without one — index-only mode, over a
            // share — it is still a real page: it is listed from the header, and
            // the archive flags itself as download-only so the caller can mark
            // the publication that way instead of lying about streaming it.
            if !entry.isStored, fileURL == nil, reader.isSolid {
                undecodable += 1
            }
            candidates.append(PageEntry(path: entry.path, byteCount: Int(entry.size)))
            index[entry.path] = entry
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.pathToEntry = index
        self.isStreamable = !reader.isSolid
        self.isDownloadOnly = undecodable > 0

        self.comicInfoData = await Self.comicInfoData(
            for: comicInfoEntry, reader: reader, fileURL: fileURL
        )
        self.comicInfo = comicInfoData.flatMap(ComicInfo.init(data:))
    }

    /// `ComicInfo.xml`'s raw bytes, read like a page — `nil` when it cannot be read,
    /// which in index-only mode is a compressed entry of a solid archive.
    private static func comicInfoData(
        for entry: RarEntry?, reader: RarReader, fileURL: URL?
    ) async -> Data? {
        guard let entry else { return nil }
        return try? await data(for: entry, reader: reader, fileURL: fileURL)
    }

    /// One entry's bytes: by range when stored, from the file when there is one, and
    /// from the entry's own ranged bytes when the archive is not solid.
    private static func data(
        for entry: RarEntry, reader: RarReader, fileURL: URL?
    ) async throws -> Data {
        if entry.isStored { return try await reader.data(for: entry) }
        if let fileURL { return try RarDecoder.data(forEntryAt: entry.path, inArchiveAt: fileURL) }
        guard !reader.isSolid else { throw ComicArchiveError.unsupportedContainer(.rar) }
        return try RarDecoder.data(ofIsolated: entry.path, in: try await reader.isolated(entry))
    }

    public var coverPage: PageEntry? {
        CoverSelection.cover(of: pages, designated: comicInfo?.coverPageIndex)
    }

    public var doublePageIndices: [Int] {
        PageDeclarations.spreads(of: pages, declared: comicInfo?.doublePageIndices ?? [])
    }

    public var chapterStartIndices: [Int] {
        PageDeclarations.chapterStarts(of: pages, declared: comicInfo?.chapterStartIndices ?? [])
    }

    public var chapterTitles: [Int: String] { comicInfo?.chapterTitles ?? [:] }

    public func data(for page: PageEntry) async throws -> Data {
        guard let entry = pathToEntry[page.path] else { throw ComicArchiveError.unreadable }
        return try await Self.data(for: entry, reader: reader, fileURL: fileURL)
    }

    /// Every listed page's bytes in one pass over the archive.
    ///
    /// For a solid archive this is the only affordable shape: reading page 30
    /// there means decompressing 1 to 29, so asking page by page would be
    /// quadratic. The indexer wants this anyway — it needs a cover and a spread
    /// check, not one page.
    public func allPageData() throws -> [String: Data] {
        guard let fileURL else { return [:] }
        return try RarDecoder.data(
            forEntriesAt: Set(pages.map(\.path)), inArchiveAt: fileURL
        )
    }
}
