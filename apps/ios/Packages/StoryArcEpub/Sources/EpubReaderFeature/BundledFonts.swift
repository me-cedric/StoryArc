internal import CoreText
internal import SwiftUI

internal import StoryArcCore
internal import StoryArcFonts

/// The bundled typefaces, in front of the app's own text stack.
///
/// `FontDeclarations` puts them in front of Readium's web view, and that is all the
/// *page* needs. Nothing puts them in front of SwiftUI — so a typeface picker asking
/// for `Font.custom("Literata")` would silently draw in the system font, which is
/// exactly the failure a typeface picker must not have.
///
/// Registration is process-scoped and happens once, on first use.
enum BundledFonts {
    /// A face's own letterforms at a *fixed* size, or the system's where it has none.
    ///
    /// The weight is always explicit. A variable font's default instance is whatever
    /// its `fvar` says, and upstream Bitter's is Thin — a specimen that let the
    /// default stand would show a hairline and call it Bitter.
    static func font(_ face: ReaderTypeface, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let family = face.cssFamily else {
            // The publisher's own. Nothing to show but the system's.
            return .system(size: size, weight: weight)
        }
        guard face.isBundled else {
            // `serif` and `sans-serif` are CSS generics, not families a platform
            // matches by name. SwiftUI has its own words for them.
            return .system(size: size, weight: weight, design: face == .serif ? .serif : .default)
        }
        _ = registered
        // `fixedSize`, not `size`: a specimen is a picture of a typeface, and one that
        // grew with Dynamic Type would outgrow the card it has to fit.
        return .custom(family, fixedSize: size).weight(weight)
    }

    /// Registers every bundled file with CoreText, once.
    ///
    /// A `static let` rather than a flag and a lock: Swift guarantees a global is
    /// initialised exactly once, so the cheapest correct answer is also the shortest.
    private static let registered: Bool = {
        let urls = ReaderTypeface.allCases
            .compactMap(\.fileStem)
            .flatMap { stem in ["", "-Italic", "-Regular", "-Bold", "-BoldItalic"].map { "\(stem)\($0)" } }
            .compactMap { StoryArcFonts.url($0) as CFURL? }
        guard !urls.isEmpty else { return false }
        return CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
    }()
}
