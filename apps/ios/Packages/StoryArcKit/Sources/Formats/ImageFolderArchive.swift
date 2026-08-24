public import Foundation

/// A directory of ordered images, read as one publication.
///
/// `publication-formats` lists a plain folder alongside the archive formats, and
/// it behaves like one: the same page filter, the same natural sort, the same
/// `ComicInfo.xml` handling. The only difference is that there is no container to
/// parse, so this is the one reader with no format work in it at all.
///
/// Subdirectories are walked, because chapters-as-folders is how unpacked comics
/// are actually laid out — and ordering by full path makes `ch10` follow `ch2`
/// for a folder exactly as it does inside a CBZ.
public struct ImageFolderArchive: ComicArchiveReading {
    public let pages: [PageEntry]
    public let skippedPageCount: Int
    /// `ComicInfo.xml` contents when the folder carries one.
    public let comicInfoData: Data?

    private let root: URL

    public init(directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw ComicArchiveError.unrecognisedContainer }

        self.root = directory.standardizedFileURL

        // Symbolic links are not followed. A publication folder is chosen by the
        // user, but it is still untrusted input: a link pointing outside the root
        // would let a crafted folder read arbitrary files, and no real comic
        // needs one.
        let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .producesRelativePathURLs]
        )

        var candidates: [PageEntry] = []
        var skipped = 0
        var comicInfo: URL?

        while let entry = walker?.nextObject() as? URL {
            let values = try? entry.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
            )
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }

            let relative = Self.relativePath(of: entry, under: root)
            if relative.lowercased().hasSuffix("comicinfo.xml") {
                comicInfo = entry
                continue
            }
            guard PageOrdering.isPage(path: relative) else { continue }

            let size = values?.fileSize ?? 0
            // A zero-length file is a page that will never decode. Counting it as
            // skipped is what lets the reader say "opened 10, skipped 2".
            if size == 0 {
                skipped += 1
                continue
            }
            candidates.append(PageEntry(path: relative, byteCount: size))
        }

        self.pages = PageOrdering.sorted(candidates)
        self.skippedPageCount = skipped
        self.comicInfoData = comicInfo.flatMap { try? Data(contentsOf: $0) }
    }

    public func data(for page: PageEntry) async throws -> Data {
        let url = root.appending(path: page.path).standardizedFileURL
        // Re-checked at read time rather than trusted from the walk: the path
        // came off a filesystem that can change between indexing and reading.
        guard url.path.hasPrefix(root.path) else { throw ComicArchiveError.unreadable }
        guard let data = try? Data(contentsOf: url) else { throw ComicArchiveError.unreadable }
        return data
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : url.lastPathComponent
    }
}
