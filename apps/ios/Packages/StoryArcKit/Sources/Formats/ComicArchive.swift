public import Foundation

internal import ZIPFoundation

/// Reading pages out of a comic archive.
///
/// `publication-formats` requires a corrupt archive to yield whatever pages can
/// be read plus a count of what was skipped, rather than refusing the whole
/// publication — so nothing here throws on a damaged entry.
public protocol ComicArchiveReading: Sendable {
    var pages: [PageEntry] { get }
    /// Entries that looked like pages but could not be read.
    var skippedPageCount: Int { get }
    /// Raw bytes for one page, or `nil` when that entry is unreadable.
    func data(for page: PageEntry) throws -> Data
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

    private let url: URL

    public init(fileAt url: URL) throws {
        self.url = url

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            // A ZIP whose central directory is gone lands here. ZIPFoundation
            // offers no partial-recovery path, so this is the honest answer:
            // the file is unreadable, and the caller reports that rather than
            // pretending it opened.
            throw ComicArchiveError.unreadable
        }

        var candidates: [PageEntry] = []
        var skipped = 0
        var comicInfo: Data?

        for entry in archive {
            let path = entry.path
            if path.lowercased().hasSuffix("comicinfo.xml") {
                comicInfo = try? Self.read(entry, from: archive)
                continue
            }
            guard PageOrdering.isPage(path: path) else { continue }
            // A zero-length entry is a page that will never decode. Counting it
            // as skipped is what lets the reader say "opened 10, skipped 2".
            if entry.uncompressedSize == 0 {
                skipped += 1
                continue
            }
            candidates.append(PageEntry(path: path, byteCount: Int(entry.uncompressedSize)))
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.comicInfoData = comicInfo
    }

    public func data(for page: PageEntry) throws -> Data {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive[page.path] else { throw ComicArchiveError.unreadable }
        return try Self.read(entry, from: archive)
    }

    /// Every page's bytes, skipping any that fail. Used by the indexer, which
    /// needs a cover and cannot afford to abort on one bad entry.
    public func readableData(for pages: [PageEntry]) -> [(page: PageEntry, data: Data)] {
        pages.compactMap { page in
            guard let data = try? data(for: page) else { return nil }
            return (page, data)
        }
    }

    private static func read(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: true) { chunk in
            data.append(chunk)
        }
        return data
    }
}

/// Opens whatever a file turns out to be.
public enum ComicArchiveOpener {
    /// Sniffs the container, then opens it. Extension is never trusted.
    public static func open(fileAt url: URL) throws -> any ComicArchiveReading {
        let container = try FormatSniffer.container(ofFileAt: url)
        guard let container else { throw ComicArchiveError.unrecognisedContainer }
        switch container {
        case .zip:
            return try ZipComicArchive(fileAt: url)
        case .rar, .sevenZip, .pdf:
            // ADR-0005: the RAR decoder needs a licence review before it ships,
            // and CB7 needs a spike. Naming the container the user actually has
            // is more useful than a generic failure.
            throw ComicArchiveError.unsupportedContainer(container)
        }
    }
}
