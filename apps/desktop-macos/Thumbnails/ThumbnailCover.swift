import CoreGraphics
import Formats
import Foundation

/// A publication's cover for Finder and Quick Look, made on this Mac from the file alone.
///
/// `desktop-experience`, *Covers in the system's file views*: a supported publication shows its
/// own cover; one with no cover, or a damaged one, gives `nil`, and the extension then answers
/// with no thumbnail so Finder keeps its generic icon. Nothing is sent anywhere and nothing is
/// written: the file is indexed and its cover decoded in memory, bounded by the size asked for.
/// Compiled into the extension and into the app, so the app's tests hold the same code. Task 5.4.
enum ThumbnailCover {
    static func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        guard maxPixelSize > 0, let publication = try? await PublicationIndexer.index(fileAt: url),
              publication.isOpenable
        else { return nil }
        if publication.format == .pdf { return try? CoverLoader.renderedCover(at: url, maxPixelSize: maxPixelSize) }
        return try? await CoverLoader.cover(for: publication, at: url, maxPixelSize: maxPixelSize)
    }
}
