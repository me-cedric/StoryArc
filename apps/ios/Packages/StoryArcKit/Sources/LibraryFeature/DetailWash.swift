internal import Foundation

internal import StoryArcCore

/// The colour a publication's own cover lends the page about it.
///
/// `publication-detail` asks for a background "derived from that cover, so the screen
/// belongs to the book", and then spends most of the requirement on the ways that goes
/// wrong: a raw extracted colour behind body text, a wash so faint or so dark the screen
/// looks broken, and a contrast floor quietly lowered to keep a colour someone liked.
///
/// So this is two adjustments, not one. ``StoryArcCore/CoverAccent`` already makes the
/// first — a dominant colour, moved in lightness until it clears 3:1 against what it sits
/// on. What it cannot make is the second, because it does not know what text will end up
/// over the result: the accent is legible *against the canvas*, and the wash is the canvas
/// blended toward it, so the wash is a third colour neither of them checked. This walks the
/// blend back until the page's own body text clears **4.5:1** against it.
///
/// 4.5 rather than the token floor of 3, and deliberately: `native-experience` puts the
/// 3:1 floor on "tertiary and accents", and what sits on this wash is running text. The
/// requirement says the floor is never lowered to keep a colour; it says nothing against
/// holding the stricter one where the stricter one applies.
///
/// The answer is a tint and a strength rather than a finished colour so the view can
/// gradient it away toward the plain canvas without recomputing anything — the blend at
/// full ``strength`` is the worst case, and it is the case that was checked.
struct DetailWash: Equatable, Sendable {
    /// The cover's colour, already adjusted to clear the token floor against the canvas.
    let tint: String
    /// How much of the canvas it takes, at the wash's strongest point.
    let strength: Double

    /// The most of the cover a page will ever show.
    ///
    /// Enough that the screen reads as belonging to the book, and far short of the point
    /// where the wash becomes a surface of its own with its own contrast problem. The loop
    /// below only ever comes *down* from here.
    static let strongest = 0.22

    /// Below this the wash is invisible and the page is better off plain.
    ///
    /// A cover whose colour cannot survive even this much dilution has, in effect, no
    /// colour to lend — and the delta would rather have the app's own accent than a wash
    /// "so faint that the screen looks broken".
    static let faintest = 0.06

    /// The wash one cover gives one palette, or `nil` when it gives none.
    ///
    /// `nil` is a real answer and the commonest one for manga: ``CoverAccent/dominant(of:)``
    /// already refuses to invent a colour for a black-and-white cover, and the page falls
    /// back to the brand accent over a plain canvas — which is what `native-experience`
    /// asks for on a surface with no publication colour of its own.
    ///
    /// - Parameters:
    ///   - pixels: the cover, sampled by ``CoverAccent/pixels(of:)``.
    ///   - canvas: the page's own background, `#rrggbb`.
    ///   - text: the body text that will sit on the washed canvas, `#rrggbb`.
    static func of(cover pixels: [UInt32], canvas: String, text: String) -> DetailWash? {
        guard let dominant = CoverAccent.dominant(of: pixels),
              // Against the canvas rather than against white: this wash is laid over the
              // page the reader is actually on, and a colour checked against a surface the
              // app never draws is a colour that was not checked.
              let tint = CoverAccent.legible(dominant, on: canvas)
        else { return nil }

        var strength = strongest
        while strength >= faintest {
            let washed = blend(tint, into: canvas, by: strength)
            if ReadingContrast.ratio(washed, text) >= ReadingContrast.aa {
                return DetailWash(tint: tint, strength: strength)
            }
            strength -= 0.02
        }
        return nil
    }

    /// `amount` of `tint` over `base`, as the compositor would draw it.
    ///
    /// Linear in the encoded channels, which is what a plain alpha composite in sRGB does —
    /// the same arithmetic SwiftUI performs, so the colour this checked is the colour the
    /// screen shows. A blend done in a different space would be a contrast check on a
    /// fourth colour that never reaches a pixel.
    static func blend(_ tint: String, into base: String, by amount: Double) -> String {
        guard let top = channels(of: tint), let bottom = channels(of: base) else { return base }
        let mixed = zip(top, bottom).map { pair in
            Int((Double(pair.0) * amount + Double(pair.1) * (1 - amount)).rounded())
        }
        return String(format: "#%02X%02X%02X", mixed[0], mixed[1], mixed[2])
    }

    private static func channels(of hex: String) -> [Int]? {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}
