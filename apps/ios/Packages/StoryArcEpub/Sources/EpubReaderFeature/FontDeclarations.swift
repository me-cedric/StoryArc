internal import ReadiumNavigator
internal import ReadiumShared

internal import StoryArcCore
internal import StoryArcFonts

/// The bundled typefaces, declared to Readium.
///
/// Readium renders a reflowable EPUB in a web view, so a family it has never heard
/// of resolves to nothing and the page silently falls back. Every bundled face has
/// to be declared with its files, its style and its weight range before the
/// preference naming it means anything.
///
/// `reading-themes` names the five, and `packages/fonts/README.md` records what
/// they cost. The four variable families each declare one upright and one italic
/// over a weight range; Atkinson Hyperlegible ships as four statics and declares
/// four faces.
enum FontDeclarations {
    /// Every declaration, for the navigator's configuration.
    static var all: [AnyHTMLFontFamilyDeclaration] {
        [
            variable(.literata, "Literata", 300...700),
            variable(.sourceSerif, "SourceSerif4", 300...700),
            variable(.ebGaramond, "EBGaramond", 400...700),
            variable(.bitter, "Bitter", 300...700),
            statics(.atkinsonHyperlegible, "AtkinsonHyperlegible"),
        ].compactMap { $0 }
    }

    /// One upright and one italic over a weight range.
    ///
    /// The range is what `packages/fonts/scripts/build.py` instanced the file down
    /// to. Declaring a wider one would ask the renderer to extrapolate weights the
    /// file no longer carries.
    private static func variable(
        _ face: ReaderTypeface,
        _ stem: String,
        _ weights: ClosedRange<Int>
    ) -> AnyHTMLFontFamilyDeclaration? {
        guard let family = face.cssFamily,
              let upright = StoryArcFonts.url(stem),
              let italic = StoryArcFonts.url("\(stem)-Italic"),
              let uprightFile = FileURL(url: upright),
              let italicFile = FileURL(url: italic)
        else { return nil }

        return CSSFontFamilyDeclaration(
            fontFamily: FontFamily(rawValue: family),
            fontFaces: [
                CSSFontFace(file: uprightFile, style: .normal, weight: .variable(weights)),
                CSSFontFace(file: italicFile, style: .italic, weight: .variable(weights)),
            ]
        ).eraseToAnyHTMLFontFamilyDeclaration()
    }

    /// Four static faces: regular, italic, bold, bold italic.
    private static func statics(
        _ face: ReaderTypeface,
        _ stem: String
    ) -> AnyHTMLFontFamilyDeclaration? {
        guard let family = face.cssFamily else { return nil }

        /// One static face: which file, and what it is.
        struct Wanted {
            let suffix: String
            let style: CSSFontStyle
            let weight: CSSFontWeight
        }

        let wanted = [
            Wanted(suffix: "Regular", style: .normal, weight: .standard(.normal)),
            Wanted(suffix: "Italic", style: .italic, weight: .standard(.normal)),
            Wanted(suffix: "Bold", style: .normal, weight: .standard(.bold)),
            Wanted(suffix: "BoldItalic", style: .italic, weight: .standard(.bold)),
        ]

        let faces: [CSSFontFace] = wanted.compactMap { face in
            guard let url = StoryArcFonts.url("\(stem)-\(face.suffix)"),
                  let file = FileURL(url: url)
            else { return nil }
            return CSSFontFace(file: file, style: face.style, weight: face.weight)
        }
        guard !faces.isEmpty else { return nil }

        return CSSFontFamilyDeclaration(
            fontFamily: FontFamily(rawValue: family),
            fontFaces: faces
        ).eraseToAnyHTMLFontFamilyDeclaration()
    }
}
