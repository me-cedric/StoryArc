package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeValues
import java.util.Locale

/**
 * The document the live preview renders.
 *
 * `reading-themes` asks the preview to be "rendered by the same engine that renders the
 * publication, so the preview cannot disagree with the result". Readium draws a reflowable
 * EPUB in a `WebView`; so does the preview. **What it is not** is a second Readium
 * navigator over the book's own resources — see [ThemePreview] for why that is not what the
 * requirement can mean, and what is lost by it.
 *
 * This object is the half that can be tested without a device: every axis the sheet can
 * move turns into one declaration here, computed from the same [ThemeValues] that
 * `ReadingTheme.preferences` hands Readium.
 *
 * iOS's `ThemePreviewDocument.swift` emits the identical document.
 */
internal object ThemePreviewDocument {

    /**
     * Where the preview's font files come from.
     *
     * `file:///android_asset/` stays reachable from a `WebView` whatever `allowFileAccess`
     * is set to, so the bundled type resolves with no server and no copy. iOS has to serve
     * the same files through a custom scheme, because `WKWebView` refuses a `file:`
     * subresource under a document loaded as a string.
     */
    const val ASSET_BASE: String = "file:///android_asset/"

    /**
     * One page of the reader, as HTML.
     *
     * @param theme the preset in force, which decides the colours and whether any override
     *   applies at all.
     * @param values the typography in force — the preset's own unless the reader moved an
     *   axis, which is why it is a parameter rather than read off the preset.
     * @param title the chapter the reader is in, or null before the book reports one.
     * @param body the words. Text from the open publication where there is one; the sample
     *   paragraph otherwise, which is what `reading-themes` asks for.
     */
    fun html(theme: ReadingTheme, values: ThemeValues, title: String?, body: String): String {
        val heading = title?.let { "<h1>${escaped(it)}</h1>" }.orEmpty()
        // Assembled line by line rather than as an indented raw string. `trimIndent` runs
        // *after* interpolation, so the stylesheet's own unindented lines would set the
        // common indent to zero and every line of the document would keep the indentation
        // it was written with — including the doctype, which then is not the first thing in
        // the file. Found by the test below, which is why it asserts the prefix.
        return listOf(
            "<!DOCTYPE html>",
            "<html><head><meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<style>",
            css(theme, values),
            "</style></head>",
            "<body><article>",
            heading,
            "<p>${escaped(body)}</p>",
            "</article></body></html>",
        ).joinToString("\n")
    }

    /**
     * Every axis, as CSS.
     *
     * The order of the two branches mirrors `ReadingTheme.preferences` exactly, including
     * the guard: Original means the publication as published, so font size is the only
     * thing that applies and nothing below the guard is emitted.
     */
    fun css(theme: ReadingTheme, values: ThemeValues): String {
        val rules = mutableListOf(
            // The base every percentage is measured from. Readium scales the publication's
            // own size by a fraction; a browser with no publication scales the root.
            "html { font-size: ${percent(values.fontSize.fraction)}; }",
            "body { margin: 0; padding: 1rem; }",
            "article { max-width: 34em; margin: 0 auto; }",
            "h1 { font-size: 1.35em; font-weight: 600; margin: 0 0 0.6em; }",
            "p { margin: 0; }",
        )

        // Original means the publication as published. Everything below this line is an
        // override, so Original takes none of it — the same guard, in the same place, as
        // the mapping that feeds the real page.
        if (theme.preset.keepsPublisherStyles) return rules.joinToString("\n")

        rules += "body { background: ${theme.background}; color: ${theme.foreground}; }"
        values.typeface.cssFamily?.let { rules += "body { font-family: ${quoted(it)}; }" }
        // A weight rather than a family: `reading-themes` says bold "raises weight without
        // changing family".
        rules += "body { font-weight: ${if (values.isBold) 700 else 400}; }"
        rules += "body { line-height: ${number(values.lineHeight)}; }"
        rules += "body { letter-spacing: ${number(values.letterSpacing)}em; }"
        rules += "body { word-spacing: ${number(values.wordSpacing)}rem; }"
        rules += "p { margin-bottom: ${number(values.paragraphSpacing)}em; }"
        // Readium's page margin is a multiplier on its own gutter; the preview's own gutter
        // is one rem, so the multiplier lands on the same quantity.
        rules += "article { padding: 0 ${number(values.pageMargins)}rem; }"
        values.textAlignment.css?.let { rules += "body { text-align: $it; }" }
        // Emitted only when the reader asked for it, for the reason the mapping passes null
        // rather than false: writing `manual` would be StoryArc turning off a publisher's
        // hyphenation on every book that wanted it.
        if (values.isHyphenated) rules += "body { -webkit-hyphens: auto; hyphens: auto; }"

        // The declaration that makes a bundled family resolve. Without it the name is a
        // word the renderer has never heard and the preview silently falls back — which
        // would make it disagree with the page on the most visible axis there is.
        val stem = values.typeface.fileStem
        val family = values.typeface.cssFamily
        if (stem != null && family != null) rules += fontFace(family, stem, values.isBold)

        return rules.joinToString("\n")
    }

    /**
     * One `@font-face`, pointing at the same asset the navigator is told to serve.
     *
     * The upright only. The preview shows two sentences of body text and no emphasis, so
     * the italic would be a second file fetched to render nothing.
     */
    private fun fontFace(family: String, stem: String, isBold: Boolean): String =
        "@font-face { font-family: ${quoted(family)}; " +
            "src: url(\"fonts/${fileName(stem, isBold)}\"); " +
            "font-weight: 300 700; font-style: normal; }"

    /**
     * Which file a family resolves to.
     *
     * The four variable families carry their whole weight range in one file, so the name is
     * the stem. Atkinson Hyperlegible ships as statics, so bold is a different file —
     * asking a static regular for 700 is what makes a renderer synthesise a smear.
     */
    fun fileName(stem: String, isBold: Boolean): String =
        if (stem == "AtkinsonHyperlegible") {
            "$stem-${if (isBold) "Bold" else "Regular"}.ttf"
        } else {
            "$stem.ttf"
        }

    /**
     * A CSS percentage, never in the reader's locale.
     *
     * A French device formats 1.15 as "1,15", and `font-size: 115,0%` is not a declaration
     * — it is a rule the renderer drops, leaving the reader's font size silently ignored in
     * the preview alone. [Locale.ROOT] is the whole fix.
     */
    private fun percent(fraction: Double): String = "${number(fraction * 100)}%"

    /**
     * Four significant figures, with the padding removed.
     *
     * Java's `%g` pads to the requested precision where C's strips it, so 1.9 arrives as
     * "1.900" here and as "1.9" on iOS. The trim closes that gap, and it only runs where
     * there is a decimal point to trim back to — "2000" must not become "2".
     */
    private fun number(value: Double): String {
        val formatted = String.format(Locale.ROOT, "%.4g", value)
        return if ('.' in formatted) formatted.trimEnd('0').trimEnd('.') else formatted
    }

    /** A family name as CSS wants it: the two generics bare, everything else quoted. */
    private fun quoted(family: String): String =
        if (family == "serif" || family == "sans-serif") family else "\"$family\""

    /**
     * Text from a publication is not to be trusted with markup.
     *
     * A chapter title carrying a `<` is a book with an odd title, not an attack — but the
     * preview builds a document out of it, and a title that closes a tag would break the
     * page rather than appear in it.
     */
    fun escaped(text: String): String =
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}

/**
 * `null` leaves the publication's own alignment in place, which is what PUBLISHER means —
 * the same shape as the Readium mapping's own null.
 */
private val ReaderTextAlignment.css: String?
    get() = when (this) {
        ReaderTextAlignment.PUBLISHER -> null
        ReaderTextAlignment.LEFT -> "left"
        ReaderTextAlignment.JUSTIFIED -> "justify"
    }
