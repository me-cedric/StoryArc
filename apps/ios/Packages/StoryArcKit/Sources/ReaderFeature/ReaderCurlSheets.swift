internal import CoreGraphics
internal import SwiftUI

internal import StoryArcCore

// What the curl is handed at a display position.
//
// Split out of `ReaderContainers` — which is at its line cap — when D14 made a sheet more
// than one decoded page. A slot may hold two facing pages, and the curl deforms one surface,
// so the two are composited before the shader ever sees them. See ``SpreadTexture``.
//
// The members are internal rather than private because `ReaderView.curled` is in the other
// file, and a `private` member of an extension cannot be reached from it.
extension ReaderView {

    /// The sheet at `display`: one page, or a spread as a single texture.
    ///
    /// `nil` until *every* page in the slot has decoded. Half a spread is not a sheet, and
    /// drawing one while the other half arrives would turn a page the reader has not seen —
    /// the caller answers that with the placeholder `page-transitions` asks for.
    func curlTexture(forDisplay display: Int) -> CGImage? {
        guard let spread = layout[slotIndex(forDisplay: display)] else { return nil }
        // Screen order, not reading order. `ReaderContainers.page(at:)` flips the same way
        // and for the same reason: a manga spread reads 4 then 5 and puts 4 on the right.
        let onScreen = isRightToLeft ? spread.pages.reversed() : spread.pages
        let decoded = onScreen.compactMap(adjustedImage(at:))
        guard decoded.count == spread.pages.count else { return nil }
        return SpreadTexture.composite(decoded)
    }

    /// A neighbouring sheet, or a matte placeholder at its expected ratio while it decodes.
    func curlSheet(at display: Int?) -> CGImage? {
        CurlPlaceholder.sheet(at: display, decoded: curlTexture(forDisplay:)) { display in
            CurlPlaceholder.image(ratio: placeholderRatio(forDisplay: display), matte: model.matte)
        }
    }

    /// Where the sheet at `display` lies flat once it is the page on screen (task 8.16).
    ///
    /// A single page opens at the reader's fit, so the turn lands on exactly the rectangle
    /// the page body then draws. A spread is two scroll views side by side, and its one
    /// composited sheet is fitted to the whole area instead.
    func curlOpening(forDisplay display: Int?) -> (CGImage, CGSize) -> CGRect {
        let isSingle = display.flatMap { layout[slotIndex(forDisplay: $0)] }?.trailing == nil
        let fit = fit
        let carried = fit == .width ? carriedZoomScale : nil
        let isRightToLeft = isRightToLeft
        return { sheet, size in
            guard isSingle else { return CGRect(origin: .zero, size: size) }
            return CurlSheetFrame.opening(
                imageSize: CGSize(width: sheet.width, height: sheet.height),
                viewport: size,
                fit: fit,
                carried: carried,
                isRightToLeft: isRightToLeft
            )
        }
    }

    /// The shape the sheet at `display` will turn out to be.
    ///
    /// A pair is twice as wide as one page, because the halves are equal — so a placeholder
    /// for a spread has to be twice as wide too, or the turn jumps when the second page
    /// arrives. That jump is the whole of what `page-transitions`' *The next page is not
    /// ready* asks a placeholder to prevent.
    private func placeholderRatio(forDisplay display: Int) -> Double {
        let spread = layout[slotIndex(forDisplay: display)]
        let page = PagePlaceholder.ratio(
            nearest: modelIndex(forDisplay: display), among: model.decodedRatios
        )
        return page * Double(spread?.pages.count ?? 1)
    }

    /// The decoded page with the series' trim and sharpness baked in, the way every other
    /// container draws it.
    ///
    /// `comic-reader` "Persisting adjustments": the curl drew the raw decode while every
    /// other container applied both halves of the reader's adjustments — this is the pixel
    /// half (border trim and sharpness); the colour half (brightness, contrast, inversion,
    /// greyscale) is a compositing operation applied once to the whole curl in
    /// ``CurledPages``, not per sheet.
    private func adjustedImage(at index: Int) -> CGImage? {
        guard let image = model.image(at: index) else { return nil }
        let trim = trimming(at: index)
        return sharpened(cropped(image, when: trim.cropsBorders), by: trim.sharpness)
    }
}
