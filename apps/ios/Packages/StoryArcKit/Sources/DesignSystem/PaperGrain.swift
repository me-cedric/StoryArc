public import SwiftUI

/// Natural's paper grain: when it is drawn, and how strong it is.
///
/// The **decision** lives here; the shader that draws it lives with the reading surface
/// that uses it, beside `PageCurl.metal` in the reader for the same reason — a shader
/// needs a resource bundle and the design system has none, and the curl already set the
/// precedent that a reader's own shader belongs to the reader.
///
/// What is here instead is everything a test can hold: the rule about when grain appears
/// at all, and the three numbers that decide what it looks like. Both readers ask this
/// type rather than each deciding for itself, which is the only way the answer stays the
/// same on a screen the reader can flip between.
public enum PaperGrain {

    // MARK: - When

    /// Whether grain may be drawn over a reading surface.
    ///
    /// Three conditions, and two of them are refusals:
    ///
    /// - **Natural is on.** Grain is Natural's texture and nothing else's. `design.md`:
    ///   the accents reach the whole app, "actual paper grain appears only where text is
    ///   read".
    /// - **Reduce Transparency is off.** `settings-and-about` requires this by name, and
    ///   the reason is not a preference: grain is a per-pixel modulation of the page, so
    ///   it lowers the effective contrast of every letterform drawn on it.
    /// - **Increase Contrast is off.** The same reason, from the other direction — a
    ///   reader who asked for more contrast is not asking for a texture that removes some.
    public static func isDrawn(
        natural: Bool,
        reduceTransparency: Bool,
        contrast: ColorSchemeContrast
    ) -> Bool {
        natural && !reduceTransparency && contrast == .standard
    }

    // MARK: - How much

    // The three numbers, in one place, because they are the whole of what a screen has to
    // judge and none of them can be judged from here. Each says what it does and how
    // confident the value is.

    /// The peak alpha of a single speck.
    ///
    /// **Unverified against a real display.** Chosen so a speck is at the edge of visible
    /// on a page at reading distance: high enough to read as stock rather than as a clean
    /// fill, low enough that body text at the smallest step does not sit in it. This is
    /// the number most likely to be wrong, and the one to move first.
    public static let intensity: Double = 0.045

    /// How many **device pixels** one noise cell covers.
    ///
    /// Device pixels rather than points, so grain is the same size on a 2× phone and a 3×
    /// one — a cell measured in points would be three physical pixels across on a Pro and
    /// two on an SE, which is two different papers. The caller divides by the display
    /// scale before handing this to the shader.
    ///
    /// **Unverified.** Below about 1 the noise starts to alias against the panel grid and
    /// shimmers when the page scrolls; above about 2.5 it stops being fibre and becomes
    /// visible dots.
    public static let cellPixels: Double = 1.5

    /// How much of the noise the second, finer octave contributes.
    ///
    /// One octave reads as television static because every speck is the same size. A
    /// second at a non-integer multiple breaks the regularity into something closer to
    /// fibre. **Unverified**, but the least risky of the three: it changes the character
    /// of the grain rather than how much of it there is.
    public static let fineOctave: Double = 0.35

    /// The noise cell in **points**, for a display at this scale.
    ///
    /// The one piece of arithmetic both platforms would otherwise do differently: Android's
    /// shader is handed pixel coordinates and iOS's is handed points.
    public static func cell(atDisplayScale scale: CGFloat) -> Double {
        cellPixels / Double(max(scale, 1))
    }
}
