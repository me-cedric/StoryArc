internal import CoreGraphics

/// A spread's two pages, composited into the one texture a curl can turn.
///
/// D14. The curl deforms a *surface*, and a surface is one texture, so a slot holding two
/// facing pages had to become one picture before `ReaderView.isPairing` could include Curl.
/// Until then Curl was excluded from the pairing and a reader in landscape lost the spread
/// the moment they chose it — which is the other half of `comic-reader`'s rule that a pair is
/// "never split across two turns".
///
/// **Equal halves, because every other container draws equal halves.**
/// `ReaderContainers.half(at:)` gives each page `maxWidth: .infinity` inside one `HStack`, and
/// its tap arithmetic says so in as many words: "the halves are equal, so a tap in one is a
/// tap in the same place on a screen twice as wide". A composite that sized each half to its
/// own page would draw a spread the reader has seen in no other mode, and would move the tap
/// zones with it.
///
/// The arithmetic is separated from the drawing so it can be asserted without a bitmap, the
/// way ``SpreadLayout`` and ``CurlTurn`` are. Android's `SpreadTexture` is the twin.
enum SpreadTexture {

    /// The composite's pixel size, and the width one half gets.
    struct Area: Equatable {
        let width: Int
        let height: Int
        let half: Int
    }

    /// The tallest page sets the height, and the widest page at that height sets the half, so
    /// neither page is enlarged past its own resolution by more than the other demands.
    static func area(of pages: [CGSize]) -> Area {
        let height = Int(pages.map(\.height).max() ?? 0)
        let half = pages
            .map { $0.height > 0 ? Int(($0.width * Double(height) / $0.height).rounded()) : 0 }
            .max() ?? 0
        return Area(width: half * pages.count, height: height, half: half)
    }

    /// Where one page lands inside the half that starts at `x`: fitted, and centred in both
    /// directions, which is what a `PageView` does inside its own half.
    static func placed(_ page: CGSize, inHalfAt x: Int, half: Int, height: Int) -> CGRect {
        guard page.width > 0, page.height > 0, half > 0, height > 0 else { return .zero }
        let scale = min(Double(half) / page.width, Double(height) / page.height)
        let fitted = CGSize(width: page.width * scale, height: page.height * scale)
        return CGRect(
            x: Double(x) + (Double(half) - fitted.width) / 2,
            y: (Double(height) - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// The pages of one slot, in screen order, as a single texture.
    ///
    /// One page is handed back untouched: a slot that is not a pair pays nothing for this,
    /// and `page-transitions`' *Memory during a curl* holds a composite only where a spread
    /// is actually on screen.
    static func composite(_ onScreen: [CGImage]) -> CGImage? {
        guard onScreen.count > 1 else { return onScreen.first }
        let pages = onScreen.map { CGSize(width: $0.width, height: $0.height) }
        let area = area(of: pages)
        guard area.width > 0, area.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: area.width,
                  height: area.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        for (position, page) in onScreen.enumerated() {
            context.draw(
                page,
                in: placed(
                    pages[position],
                    inHalfAt: position * area.half,
                    half: area.half,
                    height: area.height
                )
            )
        }
        return context.makeImage()
    }
}
