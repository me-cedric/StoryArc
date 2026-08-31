package app.storyarc.feature.epubreader

import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.values
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the live preview draws.
 *
 * `reading-themes` asks the preview to be "rendered by the same engine that renders the
 * publication, so the preview cannot disagree with the result". The engine is the same by
 * construction — both are a `WebView`. What is *not* free is the numbers, and this is where
 * they are held: every axis is asserted to reach the preview's CSS carrying the value the
 * reader set.
 *
 * iOS's `ThemePreviewDocumentTests` asserts the same document, and makes one comparison
 * this cannot: `EpubPreferences` needs a device here, so the cross-check against the real
 * Readium mapping lives on that side only. What holds the two documents together instead is
 * that they are asserted against the same strings.
 */
class ThemePreviewDocumentTest {

    private val original = Locale.getDefault()

    @After
    fun restoreLocale() {
        Locale.setDefault(original)
    }

    /** Every axis moved off its default, so a rule that silently emitted a constant fails. */
    private val moved = ThemeValues(
        typeface = ReaderTypeface.BITTER,
        fontSize = FontSizeStep.LARGE,
        isBold = true,
        lineHeight = 1.9,
        letterSpacing = 0.12,
        wordSpacing = 0.3,
        paragraphSpacing = 1.4,
        pageMargins = 2.1,
        textAlignment = ReaderTextAlignment.JUSTIFIED,
        isHyphenated = true,
    )

    @Test
    fun `every axis the sheet can move reaches the preview's CSS`() {
        val css = ThemePreviewDocument.css(ReadingTheme(ThemePreset.PAPER), moved)

        assertTrue(css, css.contains("font-size: 115%"))
        assertTrue(css, css.contains("font-family: \"Bitter\""))
        assertTrue(css, css.contains("font-weight: 700"))
        assertTrue(css, css.contains("line-height: 1.9"))
        assertTrue(css, css.contains("letter-spacing: 0.12em"))
        assertTrue(css, css.contains("word-spacing: 0.3rem"))
        assertTrue(css, css.contains("margin-bottom: 1.4em"))
        assertTrue(css, css.contains("padding: 0 2.1rem"))
        assertTrue(css, css.contains("text-align: justify"))
        assertTrue(css, css.contains("hyphens: auto"))
    }

    @Test
    fun `a comma decimal separator never reaches the stylesheet`() {
        // A French device formats 1.9 as "1,9", and `line-height: 1,9` is not a declaration
        // — it is a rule the renderer drops, leaving the reader's spacing silently ignored
        // in the preview alone. This is the one bug in this file a screenshot would not
        // catch, because the screenshot would be taken in English.
        Locale.setDefault(Locale.FRANCE)
        val css = ThemePreviewDocument.css(ReadingTheme(ThemePreset.PAPER), moved)

        assertTrue(css, css.contains("line-height: 1.9"))
        assertFalse(css, css.contains("1,9"))
    }

    @Test
    fun `the colours are the theme's, and the theme is where the page gets them`() {
        val theme = ReadingTheme(ThemePreset.CALM)
        val css = ThemePreviewDocument.css(theme, theme.preset.values)

        // `background` and `foreground` are the same two properties `ReadingTheme.preferences`
        // hands Readium, so the preview and the page cannot show different colours.
        assertTrue(css, css.contains(theme.background))
        assertTrue(css, css.contains(theme.foreground))
    }

    @Test
    fun `Original overrides nothing but size, in the preview as on the page`() {
        val theme = ReadingTheme(ThemePreset.ORIGINAL)
        val values = theme.preset.values.copy(fontSize = FontSizeStep.HUGE)
        val css = ThemePreviewDocument.css(theme, values)

        assertTrue(css, css.contains("font-size: 175%"))
        // The same guard in the same place: nothing below it is emitted.
        assertFalse(css, css.contains("line-height"))
        assertFalse(css, css.contains("text-align"))
        assertFalse(css, css.contains("background"))
        assertFalse(css, css.contains("@font-face"))
    }

    @Test
    fun `publisher and system faces are named without a declaration behind them`() {
        // The two generics resolve to the platform's own faces and are written bare; the
        // publisher's own means "override nothing", so no family is emitted at all.
        val paper = ReadingTheme(ThemePreset.PAPER)

        val serif = ThemePreviewDocument.css(
            paper,
            ThemeValues(typeface = ReaderTypeface.SERIF),
        )
        assertTrue(serif, serif.contains("font-family: serif"))
        assertFalse(serif, serif.contains("@font-face"))

        val publisher = ThemePreviewDocument.css(
            paper,
            ThemeValues(typeface = ReaderTypeface.PUBLISHER),
        )
        assertFalse(publisher, publisher.contains("font-family"))
        assertFalse(publisher, publisher.contains("@font-face"))
    }

    @Test
    fun `a bundled face brings the asset the navigator is already told to serve`() {
        val css = ThemePreviewDocument.css(
            ReadingTheme(ThemePreset.PAPER),
            ThemeValues(typeface = ReaderTypeface.LITERATA, isBold = true),
        )

        // The same path `FontDeclarations` gives the navigator, under the asset base a
        // WebView can always reach.
        assertTrue(css, css.contains("url(\"fonts/Literata.ttf\")"))
        assertEquals("file:///android_asset/", ThemePreviewDocument.ASSET_BASE)
    }

    @Test
    fun `a static family brings the right weight and a variable one brings one file`() {
        // Asking Atkinson's regular file for 700 is what makes a renderer synthesise a
        // smear, so bold is a different file. The four variable families carry their whole
        // range in one.
        assertEquals(
            "AtkinsonHyperlegible-Regular.ttf",
            ThemePreviewDocument.fileName("AtkinsonHyperlegible", isBold = false),
        )
        assertEquals(
            "AtkinsonHyperlegible-Bold.ttf",
            ThemePreviewDocument.fileName("AtkinsonHyperlegible", isBold = true),
        )
        assertEquals("Literata.ttf", ThemePreviewDocument.fileName("Literata", isBold = true))
    }

    @Test
    fun `hyphenation is emitted only when asked for, as the mapping leaves it null`() {
        // Writing `manual` would be StoryArc turning off a publisher's hyphenation on every
        // book that wanted it — the reason the mapping passes null rather than false.
        val paper = ReadingTheme(ThemePreset.PAPER)
        val values = paper.preset.values.copy(isHyphenated = false)

        assertFalse(ThemePreviewDocument.css(paper, values).contains("hyphens"))
    }

    @Test
    fun `a chapter title cannot close a tag`() {
        // A book with `<` in its chapter title is an odd book, not an attack — but the
        // preview builds a document out of it, and a title that closed a tag would break
        // the page rather than appear in it.
        val html = ThemePreviewDocument.html(
            theme = ReadingTheme(ThemePreset.PAPER),
            values = ThemeValues(),
            title = "<script>alert(1)</script> & Sons",
            body = "2 < 3",
        )

        assertFalse(html, html.contains("<script>"))
        assertTrue(html, html.contains("&lt;script&gt;"))
        assertTrue(html, html.contains("&amp; Sons"))
        assertTrue(html, html.contains("2 &lt; 3"))
    }

    @Test
    fun `the document carries both halves of the specimen, and omits a title it lacks`() {
        // `reading-themes`: "a chapter title and at least three lines of body text".
        val withTitle = ThemePreviewDocument.html(
            theme = ReadingTheme(ThemePreset.QUIET),
            values = ThemeValues(),
            title = "Chapter Two",
            body = "The light had gone out of the afternoon.",
        )
        assertTrue(withTitle, withTitle.contains("<h1>Chapter Two</h1>"))
        assertTrue(withTitle, withTitle.contains("The light had gone out of the afternoon."))
        assertTrue(withTitle, withTitle.startsWith("<!DOCTYPE html>"))

        val without = ThemePreviewDocument.html(
            theme = ReadingTheme(ThemePreset.PAPER),
            values = ThemeValues(),
            title = null,
            body = "Sample.",
        )
        assertFalse(without, without.contains("<h1>"))
        assertTrue(without, without.contains("Sample."))
    }
}
