public import CoreGraphics
public import Foundation

internal import ImageIO
internal import UniformTypeIdentifiers

/// Covers kept on disk, so a library that has been opened before opens without reading
/// every archive again.
///
/// `sources` asks for a cover to be "stored on disk at display resolution for the device",
/// and for the cover cache to be "evictable under storage pressure independently of
/// downloaded publications". Both fall out of *where* this writes: the caches directory is
/// the one the system reclaims on its own, and downloads live in Application Support and
/// are excluded from backup. Clearing one has never touched the other, and the Privacy
/// screen already counts and clears this directory under "Cache".
///
/// Until this existed the cover of every publication was extracted again on every launch —
/// a ZIP opened, a central directory read, an entry inflated and an image decoded, per
/// cover, to draw a grid the reader had already seen.
///
/// Android's `CoverCache` writes the same files for the same reasons.
public struct CoverCache: Sendable {

    /// What a cover is written as.
    ///
    /// JPEG rather than the source's own format: a cover is a photograph-like image shown
    /// at a few hundred points, the archive's PNG is often several megabytes, and the point
    /// of this cache is to be cheaper than the thing it replaces. Quality is high enough
    /// that the compression is not the reason a cover looks soft.
    private static let quality: CGFloat = 0.85

    /// The data-protection class the covers directory is written under.
    ///
    /// A cover is a cache, and it is also the title of a book on a reader's shelf.
    /// The system default leaves both readable off a device taken while locked, so
    /// this directory carries the same class the downloads do — `.completeUnlessOpen`
    /// rather than `.complete`, because the app is woken to finish a background
    /// transfer while the device is locked and the publication indexed at that
    /// moment writes its cover here. See ``DownloadStore/fileProtection`` for the
    /// full argument; the two are deliberately the same value.
    public static let fileProtection: FileProtectionType = .completeUnlessOpen

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? URL.cachesDirectory.appending(path: "covers", directoryHint: .isDirectory)
    }

    /// Where one cover lives.
    ///
    /// Keyed by the pixel size as well as the publication, because "display resolution" is
    /// a property of the device *and* the layout: the grid and the list ask for different
    /// sizes, and a cover cached for one must not be served upscaled to the other.
    ///
    /// The identity is hashed rather than used directly. A publication id can carry a path,
    /// and a path carries separators — a file name is not a place to find that out.
    private func file(for id: String, maxPixelSize: Int) -> URL {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(id.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return directory.appending(path: "\(String(hash, radix: 36))-\(maxPixelSize).jpg")
    }

    /// The cover already on disk, if there is one at this size.
    public func image(for id: String, maxPixelSize: Int) -> CGImage? {
        let url = file(for: id, maxPixelSize: maxPixelSize)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Writes a cover, replacing whatever was there.
    ///
    /// Failure is silent and correct: this is a cache. A device with no room left should
    /// draw the library, not refuse to.
    public func store(_ image: CGImage, for id: String, maxPixelSize: Int) {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.fileProtection]
        )
        // Set again rather than only at creation: the attribute above applies only
        // when this call is the one that makes the directory, and a covers
        // directory made before the class was chosen would otherwise keep the
        // system default until the reader cleared their cache.
        try? FileManager.default.setAttributes(
            [.protectionKey: Self.fileProtection], ofItemAtPath: directory.path
        )
        let url = file(for: id, maxPixelSize: maxPixelSize)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: Self.quality] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
    }

    /// Forgets every cover. The Privacy screen's "Clear cache", and the tests.
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
