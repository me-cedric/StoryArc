public import CoreGraphics
public import Foundation

public import StoryArcCore

internal import ImageIO
internal import UniformTypeIdentifiers

/// The one place that answers "what is this publication's cover".
///
/// Task 1.3 of `cover-for-every-publication`. The shelf, the player, the media session and
/// the publication page each resolved covers for themselves, so a new rung had to be taught
/// to four callers or it reached three of them — which is how a reader could choose a cover,
/// see it on the shelf, and still get a glyph on the lock screen. They ask this instead.
///
/// The rungs, cheapest first, exactly as `cover-art`'s *The cover ladder* orders them:
///
/// 1. **The reader's own picture**, from ``CoverOverrideStore``. It is above the bytes rather
///    than below them because the reader chose it over what the bytes say.
/// 2. **The publication's own bytes**, through ``CoverLoader``.
/// 3. **A loose cover image beside the file**, through ``LooseCover``.
///
/// What is deliberately *not* here is the server rung and the lookup rung. A Kavita chapter's
/// cover needs that source's credential and its certificate pins, which belong to the library
/// rather than to the format layer; `LibraryModel.cover(for:maxPixelSize:)` keeps that rung
/// where its dependencies already are, and asks this one for everything on the device.
public struct CoverLadder: Sendable {

    private let overrides: CoverOverrideStore

    public init(overrides: CoverOverrideStore = CoverOverrideStore()) {
        self.overrides = overrides
    }

    /// The reader's own picture for this publication, decoded and bounded, or nil where they
    /// have chosen none.
    ///
    /// The top rung on its own, for a caller that holds a cache of its own in front of the
    /// ladder: `LibraryModel.cover(for:maxPixelSize:)` reads a decoded cover off disk by
    /// identity and size, and that cache cannot know a reader replaced the picture behind it.
    /// Asking this first is what makes a chosen cover appear at once rather than on the next
    /// cache clear, and it is also the only rung a server row can reach — such a row has no
    /// file on this device for the rungs below to read.
    public func chosenCover(for publication: Publication, maxPixelSize: Int) async -> CGImage? {
        guard let chosen = overrides.data(for: publication) else { return nil }
        return try? PageDecoder.decode(chosen, maxPixelSize: maxPixelSize)
    }

    /// The publication's cover, decoded and bounded, or nil where no rung answers.
    ///
    /// Nil rather than a throw: every caller draws ``CoverlessWell`` for an absent cover, and
    /// a missing cover is a normal state rather than a failure. `url` is where the library
    /// recorded this publication; nil is a server row, which has no file on this device — its
    /// override still answers, which is what lets a reader set a cover on one.
    public func cover(
        for publication: Publication, at url: URL?, maxPixelSize: Int
    ) async -> CGImage? {
        if let image = await chosenCover(for: publication, maxPixelSize: maxPixelSize) {
            return image
        }
        guard let url else { return nil }
        if let image = try? await CoverLoader.anyCover(
            for: publication, at: url, maxPixelSize: maxPixelSize
        ) {
            return image
        }
        guard let loose = LooseCover.beside(url),
              let data = try? Data(contentsOf: loose)
        else { return nil }
        return try? PageDecoder.decode(data, maxPixelSize: maxPixelSize)
    }

    /// The file the publication's artwork lives in, for a caller that needs a path rather
    /// than pixels — the media session hands one to the system, which draws it itself.
    ///
    /// The same ladder, stopping at the rungs that are already files: a chosen cover, the
    /// artwork the indexer wrote out for an audiobook, then a loose image beside the file.
    /// A comic's cover is an entry inside an archive and has no path of its own, so this
    /// answers nil for one — which is what it answered before this existed.
    public func coverFile(for publication: Publication, at url: URL?) -> URL? {
        if let chosen = overrides.file(for: publication) { return chosen }
        if let path = publication.coverPath, publication.format.isAudio,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return url.flatMap(LooseCover.beside)
    }
}

/// Turning a picture the reader picked into a cover.
///
/// `cover-art`: "the chosen picture is cropped to the cover shape before it is stored". A
/// photograph is 4:3 or 3:4 and a cover is 2:3, so an uncropped choice is letterboxed into
/// every cell on the shelf beside covers that are not — the artwork is the interface, and a
/// shelf where one cell has grey bars down its sides is a shelf with a mistake on it.
public enum CoverArtwork {

    /// The printed proportion every cover-shaped cell in this app draws.
    public static let aspectRatio: CGFloat = 2.0 / 3.0

    private static let quality: CGFloat = 0.9

    /// The longest side a stored cover keeps. The publication page asks for 900 pixels;
    /// this leaves room for a large iPad without storing a 48-megapixel photograph whole.
    public static let maxSide = 1600

    /// The largest picture this app reads at all. A picked file is untrusted input.
    public static let maxBytes = 40 * 1024 * 1024

    /// `data` turned upright, centre-cropped to the cover shape, bounded to ``maxSide`` and
    /// re-encoded, or nil when it is too large or not an image this app can decode.
    ///
    /// A thumbnail decode rather than a full one, for two reasons in one call. A phone
    /// writes a portrait photograph as a landscape bitmap plus an EXIF orientation, and
    /// `kCGImageSourceCreateThumbnailWithTransform` is what applies it — a plain decode
    /// stores the reader's cover lying on its side. And the thumbnail is decoded at its
    /// bounded size, so a 48-megapixel photograph is never held whole.
    ///
    /// Centre rather than anything cleverer: a cover's subject is in the middle of it, and
    /// face detection on a book jacket finds the author's photograph on the back.
    public static func coverShaped(_ data: Data) -> Data? {
        guard data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxSide,
              ] as CFDictionary)
        else { return nil }
        return encoded(cropped(image))
    }

    /// `image` centre-cropped to the cover shape, or unchanged when it already is one.
    public static func cropped(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return image }
        let side = width / height > aspectRatio
            ? CGSize(width: height * aspectRatio, height: height)
            : CGSize(width: width, height: width / aspectRatio)
        let rect = CGRect(
            x: ((width - side.width) / 2).rounded(),
            y: ((height - side.height) / 2).rounded(),
            width: side.width.rounded(),
            height: side.height.rounded()
        )
        return image.cropping(to: rect) ?? image
    }

    private static func encoded(_ image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}
