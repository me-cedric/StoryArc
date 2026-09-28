public import Foundation

/// A CBR.
///
/// Indexes on headers alone: `RarReader` parses names, sizes and flags without a
/// decoder, so a remote CBR is catalogued without downloading it. Reading a
/// *compressed* page needs `RarDecoder`, which is the only place libarchive is
/// used and the only part that needs a local file.
///
/// That split is why this type takes an optional URL. Given one, every page is
/// readable. Without one — a remote source not yet downloaded — stored pages read
/// and compressed pages count as skipped, which is what `publication-formats`
/// means by opening what can be read and reporting what was not.
///
/// Split out of `ComicArchive.swift`, which had reached the 400-line cap this
/// project enforces — this is the one archive kind with nothing left in common
/// with the other two: no `ComicInfo`, so no spreads and no chapters either.
public struct RarComicArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    public let generation: RarGeneration
    /// Whether pages can be read out of order from a remote source.
    ///
    /// False for a solid archive, which has to be decompressed from the start.
    /// `Streaming capability per format` requires flagging that before the user
    /// taps a remote publication, rather than discovering it mid-read.
    public let isStreamable: Bool

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
        var index: [String: RarEntry] = [:]

        for entry in reader.entries where PageOrdering.isPage(path: entry.path) {
            // A compressed entry is readable only with a local file to hand to
            // libarchive. Without one it is a page we can see and cannot read, so
            // it counts as skipped rather than failing later.
            let readable = entry.isStored || fileURL != nil
            guard readable, entry.size > 0 else {
                skipped += 1
                continue
            }
            candidates.append(PageEntry(path: entry.path, byteCount: Int(entry.size)))
            index[entry.path] = entry
        }

        guard !candidates.isEmpty || skipped == 0 else {
            // Pages exist but none can be read. That is a decoder gap, not a
            // damaged file, so it is named as the container it is.
            throw ComicArchiveError.unsupportedContainer(.rar)
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.pathToEntry = index
        self.isStreamable = !reader.isSolid
    }

    public func data(for page: PageEntry) async throws -> Data {
        guard let entry = pathToEntry[page.path] else { throw ComicArchiveError.unreadable }
        if entry.isStored { return try await reader.data(for: entry) }
        guard let fileURL else { throw ComicArchiveError.unsupportedContainer(.rar) }
        return try RarDecoder.data(forEntryAt: entry.path, inArchiveAt: fileURL)
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
