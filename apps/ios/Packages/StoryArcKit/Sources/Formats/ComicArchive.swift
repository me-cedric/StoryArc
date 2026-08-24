public import Foundation

/// Reading pages out of a comic archive.
///
/// Async throughout because the bytes may be arriving from an SMB share or an
/// HTTP range request — ADR-0008 makes the source an abstraction, and this is
/// the layer that stops caring where pages come from.
///
/// `publication-formats` requires a corrupt archive to yield whatever pages can
/// be read plus a count of what was skipped, rather than refusing the whole
/// publication.
public protocol ComicArchiveReading: Sendable {
    var pages: [PageEntry] { get }
    /// Entries that looked like pages but could not be read.
    var skippedPageCount: Int { get }
    /// Raw bytes for one page.
    func data(for page: PageEntry) async throws -> Data
}

public enum ComicArchiveError: Error, Equatable {
    /// The container is one StoryArc recognises but cannot read yet.
    case unsupportedContainer(FormatSniffer.Container)
    /// Nothing recognisable at all.
    case unrecognisedContainer
    /// The archive needs a password. `publication-formats` requires StoryArc to
    /// say so rather than prompt, because it does not manage archive passwords.
    case passwordProtected
    /// Not a single entry could be read, damaged beyond partial recovery.
    case unreadable
    /// A solid archive that cannot be read at all. Named separately from
    /// `unsupportedContainer` because the container *is* supported and this
    /// particular file still cannot be read.
    ///
    /// Solid RAR4 only. libarchive reads a solid RAR5 completely; it refuses a
    /// solid RAR4 outright. See the finding in the format change's task list.
    case solidArchive
}

/// A CBZ, or anything else that turns out to be a ZIP — including a file named
/// `.cbr` that is really a ZIP, which the format spec requires to open.
public struct ZipComicArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    /// `ComicInfo.xml` contents when the archive carries one.
    public let comicInfoData: Data?
    /// True when the archive's index was rebuilt by scanning, because its central
    /// directory was gone. The pages are real; the count may be short.
    public let isRecovered: Bool

    private let reader: ZipReader
    private let pathToEntry: [String: ZipEntry]

    public init(source: any RandomAccessSource) async throws {
        do {
            self.reader = try await ZipReader(source: source)
        } catch ZipError.noCentralDirectory {
            // A ZIP whose central directory is gone — a truncated download, a
            // partial copy. `publication-formats` requires opening whatever can be
            // read rather than refusing the publication, and owning the reader is
            // what makes that possible (ADR-0008). The scan is linear, which is
            // inherent: recovery exists because there is no index to seek with.
            do {
                self.reader = try await ZipReader.recovering(source: source)
            } catch {
                throw ComicArchiveError.unreadable
            }
        }
        self.isRecovered = reader.isRecovered

        var candidates: [PageEntry] = []
        var skipped = 0
        var comicInfo: ZipEntry?
        var index: [String: ZipEntry] = [:]

        for entry in reader.entries {
            if entry.path.lowercased().hasSuffix("comicinfo.xml") {
                comicInfo = entry
                continue
            }
            guard PageOrdering.isPage(path: entry.path) else { continue }
            if entry.isEncrypted {
                // `publication-formats`: state that the archive is protected
                // rather than prompting. One encrypted page means the archive is.
                throw ComicArchiveError.passwordProtected
            }
            // A zero-length entry is a page that will never decode. Counting it
            // as skipped is what lets the reader say "opened 10, skipped 2".
            //
            // In a recovered archive a zero *uncompressed* size means unknown
            // rather than empty — a local header with a data descriptor declares
            // none — so what matters there is whether any bytes survived.
            let hasBytes = reader.isRecovered ? entry.compressedSize > 0 : entry.uncompressedSize > 0
            if !hasBytes {
                skipped += 1
                continue
            }
            // A recovered entry's uncompressed size is often unknown, so the
            // compressed size stands in. It is a lower bound on the page, which is
            // better than zero for laying out a placeholder.
            let byteCount = entry.uncompressedSize > 0 ? entry.uncompressedSize : entry.compressedSize
            candidates.append(PageEntry(path: entry.path, byteCount: Int(byteCount)))
            index[entry.path] = entry
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.pathToEntry = index
        if let comicInfo {
            self.comicInfoData = try await reader.data(for: comicInfo)
        } else {
            self.comicInfoData = nil
        }
    }

    public func data(for page: PageEntry) async throws -> Data {
        guard let entry = pathToEntry[page.path] else { throw ComicArchiveError.unreadable }
        return try await reader.data(for: entry)
    }

    /// Every page's bytes, skipping any that fail. Used by the indexer, which
    /// needs a cover and cannot afford to abort on one bad entry.
    public func readableData(for pages: [PageEntry]) async -> [(page: PageEntry, data: Data)] {
        var results: [(page: PageEntry, data: Data)] = []
        for page in pages {
            if let data = try? await data(for: page) { results.append((page, data)) }
        }
        return results
    }
}

/// A CBT. TAR carries no compression and no encryption, so opening one is
/// header parsing and nothing else — see `TarReader` for why this needs no C.
public struct TarComicArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    /// `ComicInfo.xml` contents when the archive carries one.
    public let comicInfoData: Data?

    private let reader: TarReader
    private let pathToEntry: [String: TarEntry]

    public init(source: any RandomAccessSource) async throws {
        do {
            self.reader = try await TarReader(source: source)
        } catch TarError.notTar {
            throw ComicArchiveError.unrecognisedContainer
        } catch {
            throw ComicArchiveError.unreadable
        }

        var candidates: [PageEntry] = []
        var skipped = 0
        var comicInfo: TarEntry?
        var index: [String: TarEntry] = [:]

        for entry in reader.entries {
            if entry.path.lowercased().hasSuffix("comicinfo.xml") {
                comicInfo = entry
                continue
            }
            guard PageOrdering.isPage(path: entry.path) else { continue }
            // A zero-length entry is a page that will never decode. Counting it
            // as skipped is what lets the reader say "opened 10, skipped 2".
            if entry.size == 0 {
                skipped += 1
                continue
            }
            candidates.append(PageEntry(path: entry.path, byteCount: Int(entry.size)))
            index[entry.path] = entry
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.pathToEntry = index
        if let comicInfo {
            self.comicInfoData = try await reader.data(for: comicInfo)
        } else {
            self.comicInfoData = nil
        }
    }

    public func data(for page: PageEntry) async throws -> Data {
        guard let entry = pathToEntry[page.path] else { throw ComicArchiveError.unreadable }
        return try await reader.data(for: entry)
    }
}

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

/// Opens whatever a file turns out to be.
public enum ComicArchiveOpener {
    /// Sniffs the container, then opens it. Extension is never trusted.
    public static func open(source: any RandomAccessSource) async throws -> any ComicArchiveReading {
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)
        guard let container = FormatSniffer.container(of: probe) else {
            throw ComicArchiveError.unrecognisedContainer
        }
        switch container {
        case .zip:
            return try await ZipComicArchive(source: source)
        case .tar:
            return try await TarComicArchive(source: source)
        case .rar:
            // No URL here, so compressed pages are reported as skipped. The
            // file-based entry point below passes one.
            return try await RarComicArchive(source: source)
        case .sevenZip, .pdf:
            // `publication-formats` requires a *named* refusal, never a generic
            // parse failure — `Container.displayName` is what carries the name.
            // 7-Zip is out of scope, and PDF has its own reader rather than an
            // archive one.
            throw ComicArchiveError.unsupportedContainer(container)
        }
    }

    /// Convenience for a local path — the only source type that exists today.
    ///
    /// A directory is routed to `ImageFolderArchive`: `publication-formats` lists
    /// a plain folder of ordered images as a publication, and from the caller's
    /// side opening one is the same action as opening a file.
    public static func open(fileAt url: URL) async throws -> any ComicArchiveReading {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return try ImageFolderArchive(directory: url)
        }
        let source = try FileSource(url: url)
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)
        // A local RAR gets its URL, which is what lets libarchive decompress a
        // page. Every other container reads through the source alone.
        if FormatSniffer.container(of: probe) == .rar {
            return try await RarComicArchive(source: source, fileURL: url)
        }
        return try await open(source: source)
    }
}
