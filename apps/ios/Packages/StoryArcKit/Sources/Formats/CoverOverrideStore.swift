public import Foundation

public import StoryArcCore

/// The cover a reader chose, kept where a cache clear cannot reach it.
///
/// Task 2.1 of `cover-for-every-publication`. Two decisions out of `design.md` are built in
/// here rather than left to the caller, because a caller that got either of them wrong would
/// lose a reader's work silently:
///
/// - **Keyed by the content digest.** `contentDigest` survives a rename and a move, and
///   `stableID` does not: it is the normalised path, so a reader who reorganises their files
///   would lose every cover they chose. Reorganising files is the normal life of a library.
/// - **Not in the caches directory.** `StorageUsage.clearCache` empties that, and a cover the
///   reader chose is not a cache — nothing can recreate it. It goes in Application Support,
///   which is the app's own data and which the system does not reclaim.
///
/// Where there is no digest — a folder of images, a server row — the key falls back to the
/// stable identifier, and ``keyKind(for:)`` says which was used so the publication page can
/// state plainly that moving this one loses the choice. A silent loss would be worse than a
/// stated limit.
public struct CoverOverrideStore: Sendable {

    /// Which identity a publication's override is filed under.
    public enum Key: Sendable, Equatable {
        /// The content digest: survives a rename and a move.
        case contentDigest
        /// The stable identifier: the publication's own path, so moving it loses the choice.
        case stableIdentifier
    }

    /// Where chosen covers are kept when nobody says otherwise.
    ///
    /// Application Support rather than Caches, and that distinction is the whole of task
    /// 2.5: `StorageUsage.clearCache` empties the caches directory, and this must survive it.
    /// Named rather than written inline so a test can assert where it is, which is the only
    /// way that promise can be checked without clearing a real reader's cache.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "cover-overrides", directoryHint: .isDirectory)
    }

    private let directory: URL

    /// - Parameter directory: where the images are kept. Nil is ``defaultDirectory``, which
    ///   is the production answer; a test hands this a temporary directory instead.
    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    /// Which identity this publication's override is filed under.
    public func keyKind(for publication: Publication) -> Key {
        publication.identity.contentDigest == nil ? .stableIdentifier : .contentDigest
    }

    /// The chosen cover's own file, or nil where the reader has chosen none.
    public func file(for publication: Publication) -> URL? {
        let url = location(for: publication)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The chosen cover's bytes, or nil where the reader has chosen none.
    public func data(for publication: Publication) -> Data? {
        file(for: publication).flatMap { try? Data(contentsOf: $0) }
    }

    /// Records `data` as this publication's cover, replacing whatever was chosen before.
    ///
    /// - Returns: the file it wrote, or nil when the write failed. A caller that got nil
    ///   should say so: unlike a cache write, this one is the reader's own choice and
    ///   dropping it quietly would leave them tapping a button that does nothing.
    @discardableResult
    public func store(_ data: Data, for publication: Publication) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = location(for: publication)
        #if os(iOS)
        // The same protection `CoverCache` gives a decoded page: a chosen cover is artwork
        // the reader put on the device, and it is readable while the app runs rather than
        // while the device is locked.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Forgets this publication's chosen cover and deletes the image.
    ///
    /// `cover-art`'s *Undoing the choice*: the ladder resolves the cover again from the rung
    /// below, and the stored image is deleted rather than orphaned.
    public func remove(for publication: Publication) {
        try? FileManager.default.removeItem(at: location(for: publication))
    }

    /// Every chosen cover, by byte count, for the storage page.
    public func sizeOnDisk() -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Hashed rather than spelled out, for the reason ``CoverCache`` already gives: a stable
    /// identifier is a path, a path carries separators, and a file name is not a place to
    /// find that out. The key's own kind is folded in so a publication that gains a digest
    /// later cannot read back the file its path wrote.
    private func location(for publication: Publication) -> URL {
        let identity = publication.identity
        let key = identity.contentDigest.map { "sha:\($0)" } ?? identity.stableID
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(key.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return directory.appending(path: String(hash, radix: 36))
    }
}
