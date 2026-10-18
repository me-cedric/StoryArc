import Foundation
import StoryArcCore
import StoryArcFonts

/// The reading faces the phones bundle, served to the renderer on the book's own scheme (`ebook-reader`, *Bundled
/// typefaces*). Every chapter the archive serves links one stylesheet of `@font-face` rules, and the faces it names
/// come from the shared `packages/fonts`, so the renderer's `fontFamily` finds them by the family name the phones use.
enum EpubFonts {
    static let folder = "storyarc-fonts/"
    static let sheet = folder + "faces.css"

    /// The variable families: an upright and an italic file over the weight range the phones declare.
    private static let variable: [(ReaderTypeface, ClosedRange<Int>)] = [
        (.literata, 300...700), (.sourceSerif, 300...700), (.ebGaramond, 400...700), (.bitter, 300...700),
    ]

    /// Atkinson Hyperlegible's four static files: the suffix, the style and the weight.
    private static let statics = [("Regular", "normal", 400), ("Italic", "italic", 400),
                                  ("Bold", "normal", 700), ("BoldItalic", "italic", 700)]

    static let css: String = {
        var rules: [String] = variable.flatMap { face, weights -> [String] in
            guard let family = face.cssFamily, let stem = face.fileStem else { return [] }
            let range = "\(weights.lowerBound) \(weights.upperBound)"
            return [rule(family, file: stem, style: "normal", weight: range),
                    rule(family, file: "\(stem)-Italic", style: "italic", weight: range)]
        }
        let atkinson = ReaderTypeface.atkinsonHyperlegible
        if let family = atkinson.cssFamily, let stem = atkinson.fileStem {
            rules += statics.map { rule(family, file: "\(stem)-\($0.0)", style: $0.1, weight: "\($0.2)") }
        }
        return rules.joined(separator: "\n")
    }()

    private static func rule(_ family: String, file: String, style: String, weight: String) -> String {
        "@font-face{font-family:\"\(family)\";src:url(\"\(file).ttf\") format(\"truetype\");"
            + "font-style:\(style);font-weight:\(weight);font-display:swap}"
    }

    /// The stylesheet, or a face file the shared package carries; nil for any other path.
    static func resource(at path: String) -> EpubResource? {
        guard path.hasPrefix(folder) else { return nil }
        let name = String(path.dropFirst(folder.count))
        if path == sheet { return EpubResource(data: Data(css.utf8), mimeType: "text/css") }
        guard name.hasSuffix(".ttf"), let url = StoryArcFonts.url(String(name.dropLast(4))),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return EpubResource(data: data, mimeType: "font/ttf")
    }

    /// A chapter with the stylesheet linked before its head closes; anything else unchanged.
    ///
    /// The `rel` carries a second token on purpose. The toolkit adds its default stylesheet (paragraph indents,
    /// heading spacing) only to a chapter with no `link[rel='stylesheet']` of its own; an exact `stylesheet` here made
    /// every unstyled book lose those defaults. A token list still loads the sheet and does not match that selector.
    static func linking(_ data: Data, mimeType: String, sheet href: String) -> Data {
        guard mimeType == "application/xhtml+xml" || mimeType == "text/html",
              let text = String(data: data, encoding: .utf8),
              let close = text.range(of: "</head>", options: .caseInsensitive)
        else { return data }
        let link = "<link rel=\"stylesheet storyarc-fonts\" type=\"text/css\" href=\"\(href)\"/>"
        return Data(text.replacingCharacters(in: close.lowerBound..<close.lowerBound, with: link).utf8)
    }
}
