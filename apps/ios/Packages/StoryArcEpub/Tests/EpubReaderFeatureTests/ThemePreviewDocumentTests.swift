import Testing

import ReadiumNavigator
import StoryArcCore
@testable import EpubReaderFeature

/// What the live preview draws, and whether it can disagree with the page.
///
/// `reading-themes` asks the preview to be "rendered by the same engine that renders the
/// publication, so the preview cannot disagree with the result". The engine is the same by
/// construction — both are a `WKWebView`. What is *not* free is the numbers, and this is
/// where they are held: every axis is asserted to reach the preview's CSS carrying the
/// same value it carries into `EPUBPreferences`.
///
/// Android's `ThemePreviewDocumentTest` asserts the same document. It cannot make the
/// second half of the comparison — `EpubPreferences` needs a device there — so the
/// cross-check against the real mapping lives on this side only.
@Suite("Theme preview document")
struct ThemePreviewDocumentTests {

    /// Every axis moved off its default, so a rule that silently emitted a constant fails.
    private var moved: ThemeValues {
        ThemeValues(
            typeface: .bitter,
            fontSize: .large,
            isBold: true,
            lineHeight: 1.9,
            letterSpacing: 0.12,
            wordSpacing: 0.3,
            paragraphSpacing: 1.4,
            pageMargins: 2.1,
            textAlignment: .justified,
            isHyphenated: true
        )
    }

    @Test("Every axis the sheet can move reaches the preview's CSS")
    func everyAxisIsEmitted() {
        let css = ThemePreviewDocument.css(theme: ReadingTheme(preset: .paper), values: moved)

        #expect(css.contains("font-size: 115%"))
        #expect(css.contains("font-family: \"Bitter\""))
        #expect(css.contains("font-weight: 700"))
        #expect(css.contains("line-height: 1.9"))
        #expect(css.contains("letter-spacing: 0.12em"))
        #expect(css.contains("word-spacing: 0.3rem"))
        #expect(css.contains("margin-bottom: 1.4em"))
        #expect(css.contains("padding: 0 2.1rem"))
        #expect(css.contains("text-align: justify"))
        #expect(css.contains("hyphens: auto"))
    }

    @Test("The preview carries the numbers the page is given, axis by axis")
    func agreesWithTheRealMapping() {
        // The one assertion that makes "the same engine" mean something. If the mapping
        // and the document ever compute a value differently, this is where it shows —
        // rather than on a screen, where a reader would have to notice it.
        let theme = ReadingTheme(preset: .calm)
        let values = moved
        let preferences = theme.preferences(values: values)
        let css = ThemePreviewDocument.css(theme: theme, values: values)

        #expect(preferences.fontSize == values.fontSize.fraction)
        #expect(css.contains("font-size: \(values.fontSize.rawValue)%"))

        #expect(preferences.lineHeight == values.lineHeight)
        #expect(css.contains("line-height: \(values.lineHeight)"))

        #expect(preferences.letterSpacing == values.letterSpacing)
        #expect(css.contains("letter-spacing: \(values.letterSpacing)em"))

        #expect(preferences.wordSpacing == values.wordSpacing)
        #expect(css.contains("word-spacing: \(values.wordSpacing)rem"))

        #expect(preferences.paragraphSpacing == values.paragraphSpacing)
        #expect(css.contains("margin-bottom: \(values.paragraphSpacing)em"))

        #expect(preferences.pageMargins == values.pageMargins)
        #expect(css.contains("padding: 0 \(values.pageMargins)rem"))

        #expect(preferences.publisherStyles == false)
        #expect(css.contains(theme.background))
        #expect(css.contains(theme.foreground))
    }

    @Test("Original overrides nothing but size, in the preview as on the page")
    func originalKeepsTheGuard() {
        let theme = ReadingTheme(preset: .original)
        var values = theme.preset.values
        values.fontSize = .huge

        let preferences = theme.preferences(values: values)
        let css = ThemePreviewDocument.css(theme: theme, values: values)

        #expect(preferences.publisherStyles == true)
        #expect(css.contains("font-size: 175%"))
        // The same guard in the same place: nothing below it is emitted.
        #expect(!css.contains("line-height"))
        #expect(!css.contains("text-align"))
        #expect(!css.contains("background"))
        #expect(!css.contains("@font-face"))
    }

    @Test("Publisher and system faces are named without a declaration behind them")
    func systemFacesNeedNoFile() {
        // The two generics resolve to the platform's own faces and are written bare;
        // the publisher's own means "override nothing", so no family is emitted at all.
        let paper = ReadingTheme(preset: .paper)

        let serif = ThemePreviewDocument.css(
            theme: paper, values: ThemeValues(typeface: .serif)
        )
        #expect(serif.contains("font-family: serif"))
        #expect(!serif.contains("@font-face"))

        let publisher = ThemePreviewDocument.css(
            theme: paper, values: ThemeValues(typeface: .publisher)
        )
        #expect(!publisher.contains("font-family"))
        #expect(!publisher.contains("@font-face"))
    }

    @Test("A bundled face brings its file, and a static family brings the right weight")
    func bundledFacesDeclareTheirFiles() {
        let paper = ReadingTheme(preset: .paper)

        let literata = ThemePreviewDocument.css(
            theme: paper, values: ThemeValues(typeface: .literata, isBold: true)
        )
        // One variable file carries the whole range, so bold changes the weight and not
        // the file.
        #expect(literata.contains("Literata.ttf"))

        // Atkinson ships as statics: asking its regular file for 700 is what makes a
        // renderer synthesise a smear, so bold is a different file.
        #expect(ThemePreviewDocument.fileName("AtkinsonHyperlegible", isBold: false)
            == "AtkinsonHyperlegible-Regular.ttf")
        #expect(ThemePreviewDocument.fileName("AtkinsonHyperlegible", isBold: true)
            == "AtkinsonHyperlegible-Bold.ttf")
        #expect(ThemePreviewDocument.fileName("Literata", isBold: true) == "Literata.ttf")
    }

    @Test("Hyphenation is emitted only when asked for, as the mapping leaves it nil")
    func hyphenationIsOptIn() {
        // Writing `manual` would be StoryArc turning off a publisher's hyphenation on
        // every book that wanted it — the reason the mapping passes nil rather than false.
        let paper = ReadingTheme(preset: .paper)
        var values = paper.preset.values
        values.isHyphenated = false

        #expect(!ThemePreviewDocument.css(theme: paper, values: values).contains("hyphens"))
        #expect(paper.preferences(values: values).hyphens == nil)
    }

    @Test("A chapter title cannot close a tag")
    func titlesAreEscaped() {
        // A book with `<` in its chapter title is an odd book, not an attack — but the
        // preview builds a document out of it, and a title that closed a tag would break
        // the page rather than appear in it.
        let html = ThemePreviewDocument.html(
            theme: ReadingTheme(preset: .paper),
            values: ThemeValues(),
            title: "<script>alert(1)</script> & Sons",
            body: "2 < 3"
        )

        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&amp; Sons"))
        #expect(html.contains("2 &lt; 3"))
    }

    @Test("The document says what it is, and carries both halves of the specimen")
    func documentShape() {
        let html = ThemePreviewDocument.html(
            theme: ReadingTheme(preset: .quiet),
            values: ThemeValues(),
            title: "Chapter Two",
            body: "The light had gone out of the afternoon."
        )

        // `reading-themes`: "a chapter title and at least three lines of body text".
        #expect(html.contains("<h1>Chapter Two</h1>"))
        #expect(html.contains("The light had gone out of the afternoon."))
        #expect(html.hasPrefix("<!DOCTYPE html>"))
    }

    @Test("A book with no chapter title yet gets a specimen rather than an empty heading")
    func missingTitleIsOmitted() {
        let html = ThemePreviewDocument.html(
            theme: ReadingTheme(preset: .paper),
            values: ThemeValues(),
            title: nil,
            body: "Sample."
        )

        #expect(!html.contains("<h1>"))
        #expect(html.contains("Sample."))
    }
}
