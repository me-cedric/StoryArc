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
public struct CoverOverrideStore: Sendable, ChosenCoverStore {

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

    /// Records `image` under `key`, replacing whatever was filed there.
    ///
    /// The key is written beside the image, because the file name is a hash and a hash cannot
    /// be turned back into the key an export has to name. ``chosen(including:)`` reads them.
    @discardableResult
    public func store(_ image: Data, forKey key: String) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = location(forKey: key)
        // The image first and the key second, so a failure between the two leaves an image no
        // export can name rather than a name with no image.
        guard write(image, to: url) else { return false }
        return write(Data(key.utf8), to: keyFile(for: url))
    }

    public func image(forKey key: String) -> Data? {
        try? Data(contentsOf: location(forKey: key))
    }

    public func remove(forKey key: String) {
        let url = location(forKey: key)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: keyFile(for: url))
    }

    /// Every chosen cover, by the key it was filed with.
    ///
    /// A cover chosen before keys were written has an image and no key file, so `candidates`
    /// are tried too: a key whose location holds an image is a cover this store can name.
    public func chosen(including candidates: [String]) -> [ChosenCover] {
        var keys = Set(candidates)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == Self.keyExtension {
            if let key = (try? Data(contentsOf: file)).flatMap({ String(bytes: $0, encoding: .utf8) }) {
                keys.insert(key)
            }
        }
        return keys.sorted().compactMap { key in
            image(forKey: key).map { ChosenCover(key: key, image: $0) }
        }
    }

    /// Records `data` as this publication's cover, replacing whatever was chosen before.
    ///
    /// - Returns: the file it wrote, or nil when the write failed. A caller that got nil
    ///   should say so: unlike a cache write, this one is the reader's own choice and
    ///   dropping it quietly would leave them tapping a button that does nothing.
    @discardableResult
    public func store(_ data: Data, for publication: Publication) -> URL? {
        let key = publication.identity.coverOverrideKey
        return store(data, forKey: key) ? location(forKey: key) : nil
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        #if os(iOS)
        // The same protection `CoverCache` gives a decoded page: a chosen cover is artwork
        // the reader put on the device, and it is readable while the app runs rather than
        // while the device is locked.
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]
        #else
        let options: Data.WritingOptions = .atomic
        #endif
        // The write's own answer, not whether a file is there afterwards. Replacing a chosen
        // cover on a full disk leaves the earlier file in place, and checking for a file
        // reported that failure as success while the old picture stayed.
        do {
            try data.write(to: url, options: options)
            return true
        } catch {
            return false
        }
    }

    /// Forgets this publication's chosen cover and deletes the image.
    ///
    /// `cover-art`'s *Undoing the choice*: the ladder resolves the cover again from the rung
    /// below, and the stored image is deleted rather than orphaned.
    public func remove(for publication: Publication) {
        remove(forKey: publication.identity.coverOverrideKey)
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
        location(forKey: publication.identity.coverOverrideKey)
    }

    private static let keyExtension = "key"

    /// The file that names the key an image is filed under.
    private func keyFile(for image: URL) -> URL {
        image.appendingPathExtension(Self.keyExtension)
    }

    private func location(forKey key: String) -> URL {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(key.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return directory.appending(path: String(hash, radix: 36))
    }
}
