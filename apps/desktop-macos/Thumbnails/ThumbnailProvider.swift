import AppKit
import QuickLookThumbnailing

/// The Quick Look thumbnail extension: Finder and Quick Look ask it for a comic's or an ebook's
/// cover. Task 5.4.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        let side = Int(max(request.maximumSize.width, request.maximumSize.height) * request.scale)
        let url = request.fileURL
        let box = request.maximumSize
        // Quick Look's reply handler may be called from any thread, once; the SDK does not
        // mark it Sendable.
        nonisolated(unsafe) let handler = handler
        Task {
            // No cover: no reply and no error, so Finder draws the generic icon and says nothing.
            guard let cover = await ThumbnailCover.image(for: url, maxPixelSize: side) else {
                return handler(nil, nil)
            }
            let size = Self.fitted(CGSize(width: cover.width, height: cover.height), in: box)
            handler(QLThumbnailReply(contextSize: size) { context in
                context.draw(cover, in: CGRect(origin: .zero, size: size))
                return true
            }, nil)
        }
    }

    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
