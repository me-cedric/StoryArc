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
    /// The page to show as the publication's cover.
    ///
    /// `publication-formats`: the first page in reading order, *unless*
    /// `ComicInfo.xml` designates a different one. Containers that carry no
    /// metadata get the default from the extension below.
    var coverPage: PageEntry? { get }
    /// Pages the container declares as double-page spreads.
    ///
    /// `comic-reader` shows such a page alone rather than pairing it, and a
    /// declaration is worth more than a guess from the aspect ratio — a wide panel
    /// scanned with margins is not a spread, and a spread scanned tight might not
    /// measure as one.
    var doublePageIndices: [Int] { get }
    /// Pages the container declares as the start of a chapter.
    ///
    /// `comic-reader`'s chapter actions (D4) move within the publication first, and
    /// this is where they find where to. `ComicInfo`'s `Bookmark` attribute, for a
    /// container that carries one.
    var chapterStartIndices: [Int] { get }
    /// The chapter's own name, by the page in ``chapterStartIndices`` it starts at.
    ///
    /// `page-browser-carousel`: the carousel names the centred page's chapter from
    /// "the marker's title". A start with no entry here has no title, and the browser
    /// falls back to its position among the chapters.
    var chapterTitles: [Int: String] { get }
}

extension ComicArchiveReading {
    public var coverPage: PageEntry? { pages.first }
    /// Nothing, for a container that carries no metadata to declare it with.
    public var doublePageIndices: [Int] { [] }
    public var chapterStartIndices: [Int] { [] }
    public var chapterTitles: [Int: String] { [:] }
}

/// Resolves what `ComicInfo.xml` says about individual pages.
public enum PageDeclarations {
    /// The declared spreads that actually name a page in this list.
    ///
    /// The same caveat as the cover: `ComicInfo`'s indices count *archive* entries, and
    /// an archive whose non-page entries were filtered out can leave a stale index
    /// behind. An index outside the page list is dropped rather than clamped, because
    /// standing an arbitrary middle page alone would look like a bug in the reader
    /// rather than in the file.
    public static func spreads(of pages: [PageEntry], declared indices: [Int]) -> [Int] {
        indices.filter { $0 >= 0 && $0 < pages.count }
    }

    /// The declared chapter starts that actually name a page in this list. Same
    /// caveat, same rule, as ``spreads(of:declared:)``.
    public static func chapterStarts(of pages: [PageEntry], declared indices: [Int]) -> [Int] {
        indices.filter { $0 >= 0 && $0 < pages.count }
    }
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
    /// The archive's parsed metadata, when it carries any.
    public let comicInfo: ComicInfo?
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
            let raw = try await reader.data(for: comicInfo)
            self.comicInfoData = raw
            self.comicInfo = ComicInfo(data: raw)
        } else {
            self.comicInfoData = nil
            self.comicInfo = nil
        }
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
    /// The archive's parsed metadata, when it carries any.
    public let comicInfo: ComicInfo?

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
            let raw = try await reader.data(for: comicInfo)
            self.comicInfoData = raw
            self.comicInfo = ComicInfo(data: raw)
        } else {
            self.comicInfoData = nil
            self.comicInfo = nil
        }
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
        return try await reader.data(for: entry)
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
            // No URL here: a non-solid archive decodes each compressed page
            // from its own ranged bytes, and a solid one needs the file-based
            // entry point below.
            return try await RarComicArchive(source: source)
        case .sevenZip, .pdf, .mp4, .mp3, .flac, .ogg, .protectedAudiobook:
            // `publication-formats` requires a *named* refusal, never a generic
            // parse failure — `Container.displayName` is what carries the name.
            // 7-Zip is out of scope, PDF has its own reader, and audio is not an
            // archive at all — naming it here already beats the unrecognised
            // container it got before, and is where the player will take over.
            throw ComicArchiveError.unsupportedContainer(container)
        }
    }

    /// Convenience for a local path — the only source type that exists today.
    ///
    /// A directory is routed to `ImageFolderArchive`: `publication-formats` lists
    /// a plain folder of ordered images as a publication, and from the caller's
    /// side opening one is the same action as opening a file.
    public static func open(fileAt url: URL) async throws -> any ComicArchiveReading {
        // The whole point of `network-share`'s streaming requirement: the archive is read
        // where the reader is looking, not fetched first.
        if let remote = try await source(for: url) {
            return try await open(source: remote)
        }
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
