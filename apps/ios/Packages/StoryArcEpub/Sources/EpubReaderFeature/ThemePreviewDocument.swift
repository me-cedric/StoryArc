internal import Foundation

internal import StoryArcCore

/// The document the live preview renders.
///
/// `reading-themes` asks the preview to be "rendered by the same engine that renders the
/// publication, so the preview cannot disagree with the result". Readium draws a
/// reflowable EPUB in a `WKWebView`; so does the preview. **What it is not** is a second
/// Readium navigator over the book's own resources — see ``ThemePreview`` for why that is
/// not what the requirement can mean, and what is lost by it.
///
/// This type is the half that can be tested without a screen: every axis the sheet can
/// move turns into one declaration here, computed from the same `ThemeValues` that
/// `ReadingTheme.preferences(values:transition:)` hands Readium.
/// `ThemePreviewDocumentTests` asserts the two against each other axis by axis, which is
/// the only thing standing between "the same engine" and "roughly the same".
///
/// Android's `ThemePreviewDocument.kt` emits the identical document.
enum ThemePreviewDocument {

    /// The scheme the preview's font files are served under.
    ///
    /// A custom scheme rather than a `file:` base URL: `WKWebView` refuses local
    /// subresources loaded from an HTML string, and the alternatives are copying two
    /// megabytes of type into a cache directory or embedding a face as base64 on every
    /// keystroke. A scheme handler reads the bytes straight out of the fonts bundle.
    /// Android needs none of this — `file:///android_asset/` is always reachable there.
    static let fontScheme = "storyarc-preview-font"

    /// One page of the reader, as HTML.
    ///
    /// - Parameters:
    ///   - theme: the preset in force, which decides the colours and whether any override
    ///     applies at all.
    ///   - values: the typography in force — the preset's own unless the reader moved an
    ///     axis, which is why it is a parameter rather than read off the preset.
    ///   - title: the chapter the reader is in, or `nil` before the book reports one.
    ///   - body: the words. Text from the open publication where there is one; the sample
    ///     paragraph otherwise, which is what `reading-themes` asks for.
    static func html(
        theme: ReadingTheme,
        values: ThemeValues,
        title: String?,
        body: String
    ) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css(theme: theme, values: values))
        </style></head>
        <body><article>
        \(title.map { "<h1>\(escaped($0))</h1>" } ?? "")
        <p>\(escaped(body))</p>
        </article></body></html>
        """
    }

    /// Every axis, as CSS.
    ///
    /// The order of the two branches mirrors `ReadingTheme.preferences(values:)` exactly,
    /// including the guard: Original means the publication as published, so font size is
    /// the only thing that applies and nothing below the guard is emitted.
    static func css(theme: ReadingTheme, values: ThemeValues) -> String {
        var rules = [
            // The base every percentage is measured from. Readium scales the publication's
            // own size by a fraction; a browser with no publication scales the root.
            "html { font-size: \(percent(values.fontSize.fraction)); }",
            "body { margin: 0; padding: 1rem; }",
            "article { max-width: 34em; margin: 0 auto; }",
            "h1 { font-size: 1.35em; font-weight: 600; margin: 0 0 0.6em; }",
            "p { margin: 0; }",
        ]

        // Original means the publication as published. Everything below this line is an
        // override, so Original takes none of it — the same guard, in the same place, as
        // the mapping that feeds the real page.
        guard !theme.preset.keepsPublisherStyles else {
            return rules.joined(separator: "\n")
        }

        rules.append("body { background: \(theme.background); color: \(theme.foreground); }")
        if let family = values.typeface.cssFamily {
            rules.append("body { font-family: \(quotedFamily(family)); }")
        }
        // A weight rather than a family: `reading-themes` says bold "raises weight without
        // changing family".
        rules.append("body { font-weight: \(values.isBold ? 700 : 400); }")
        rules.append("body { line-height: \(number(values.lineHeight)); }")
        rules.append("body { letter-spacing: \(number(values.letterSpacing))em; }")
        rules.append("body { word-spacing: \(number(values.wordSpacing))rem; }")
        rules.append("p { margin-bottom: \(number(values.paragraphSpacing))em; }")
        // Readium's page margin is a multiplier on its own gutter; the preview's own
        // gutter is one rem, so the multiplier lands on the same quantity.
        rules.append("article { padding: 0 \(number(values.pageMargins))rem; }")
        if let align = values.textAlignment.css {
            rules.append("body { text-align: \(align); }")
        }
        // Emitted only when the reader asked for it, for the reason the mapping passes nil
        // rather than false: writing `manual` would be StoryArc turning off a publisher's
        // hyphenation on every book that wanted it.
        if values.isHyphenated {
            rules.append("body { -webkit-hyphens: auto; hyphens: auto; }")
        }

        // The declaration that makes a bundled family resolve. Without it the name is a
        // word the renderer has never heard and the preview silently falls back — which
        // would make it disagree with the page on the most visible axis there is.
        if let stem = values.typeface.fileStem, let family = values.typeface.cssFamily {
            rules.append(fontFace(family: family, stem: stem, isBold: values.isBold))
        }

        return rules.joined(separator: "\n")
    }

    /// One `@font-face`, pointing at the bundled file through the preview's own scheme.
    ///
    /// The upright only. The preview shows two sentences of body text and no emphasis, so
    /// the italic would be a second file fetched to render nothing.
    private static func fontFace(family: String, stem: String, isBold: Bool) -> String {
        """
        @font-face { \
        font-family: \(quotedFamily(family)); \
        src: url("\(fontScheme)://\(fileName(stem, isBold: isBold))"); \
        font-weight: 300 700; \
        font-style: normal; }
        """
    }

    /// Which file a family resolves to.
    ///
    /// The four variable families carry their whole weight range in one file, so the name
    /// is the stem. Atkinson Hyperlegible ships as statics, so bold is a different file —
    /// asking a static regular for 700 is what makes a renderer synthesise a smear.
    static func fileName(_ stem: String, isBold: Bool) -> String {
        stem == "AtkinsonHyperlegible"
            ? "\(stem)-\(isBold ? "Bold" : "Regular").ttf"
            : "\(stem).ttf"
    }

    // MARK: - Formatting

    /// A CSS percentage, never in the reader's locale.
    ///
    /// A French device formats 1.15 as "1,15", and `font-size: 115,0%` is not a
    /// declaration — it is a rule the renderer drops, leaving the reader's font size
    /// silently ignored in the preview alone.
    private static func percent(_ fraction: Double) -> String {
        "\(number(fraction * 100))%"
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4g", value)
    }

    /// A family name as CSS wants it: the two generics bare, everything else quoted.
    private static func quotedFamily(_ family: String) -> String {
        family == "serif" || family == "sans-serif" ? family : "\"\(family)\""
    }

    /// Text from a publication is not to be trusted with markup.
    ///
    /// A chapter title carrying a `<` is a book with an odd title, not an attack — but the
    /// preview builds a document out of it, and a title that closes a tag would break the
    /// page rather than appear in it.
    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension EpubReaderModel {
    /// Words from where the reader is, for the preview to set.
    ///
    /// `reading-themes`: the preview "uses text from the open publication where one is
    /// open, and representative sample text otherwise" — so this returns empty rather than
    /// a substitute, and the view supplies the sample. Read from the resource the reader
    /// is in, through the same path a bookmark's excerpt takes.
    ///
    /// Long enough for the several lines the requirement asks for, and no longer: a
    /// preview two hundred points tall shows about six of them, and the rest would be text
    /// nobody sees being escaped on every slider step.
    func previewExcerpt() async -> String {
        guard let locator else { return "" }
        guard let markup = await Self.markup(of: opened, at: locator.href.removingFragment())
        else { return "" }
        return Excerpt.at(
            Excerpt.plainText(markup),
            fraction: locator.locations.progression ?? 0,
            length: 320
        )
    }
}

private extension ReaderTextAlignment {
    /// `nil` leaves the publication's own alignment in place, which is what
    /// `publisher` means — the same shape as the Readium mapping's own `nil`.
    var css: String? {
        switch self {
        case .publisher: nil
        case .left: "left"
        case .justified: "justify"
        }
    }
}
