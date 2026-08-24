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
}

/// A CBZ, or anything else that turns out to be a ZIP — including a file named
/// `.cbr` that is really a ZIP, which the format spec requires to open.
public struct ZipComicArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    /// `ComicInfo.xml` contents when the archive carries one.
    public let comicInfoData: Data?

    private let reader: ZipReader
    private let pathToEntry: [String: ZipEntry]

    public init(source: any RandomAccessSource) async throws {
        do {
            self.reader = try await ZipReader(source: source)
        } catch ZipError.noCentralDirectory {
            // A ZIP whose central directory is gone. Our own reader makes
            // forward-scanning recovery *possible* — see ADR-0008 — but that is
            // not implemented yet, so this stays honest rather than optimistic.
            throw ComicArchiveError.unreadable
        }

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
            if entry.uncompressedSize == 0 {
                skipped += 1
                continue
            }
            candidates.append(PageEntry(path: entry.path, byteCount: Int(entry.uncompressedSize)))
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
        case .rar, .sevenZip, .pdf:
            // `publication-formats` requires a *named* refusal, never a generic
            // parse failure — `Container.displayName` is what carries the name.
            // RAR needs a decoder (ADR-0005), 7-Zip is out of scope, and PDF has
            // its own reader rather than an archive one.
            throw ComicArchiveError.unsupportedContainer(container)
        }
    }

    /// Convenience for a local file — the only source type that exists today.
    public static func open(fileAt url: URL) async throws -> any ComicArchiveReading {
        try await open(source: try FileSource(url: url))
    }
}
