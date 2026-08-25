package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReaderTypeface
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.ExperimentalReadiumApi

/**
 * The bundled typefaces, declared to Readium.
 *
 * Readium renders a reflowable EPUB in a `WebView`, so a family it has never heard
 * of resolves to nothing and the page silently falls back. Every bundled face has to
 * be declared with its files, its style and its weight range — and its directory has
 * to be served — before the preference naming it means anything.
 *
 * `reading-themes` names the five, and `packages/fonts/README.md` records what they
 * cost. iOS's `FontDeclarations.swift` declares the same five the same way.
 */
@OptIn(ExperimentalReadiumApi::class)
internal fun EpubNavigatorFragment.Configuration.declareBundledFonts() {
    // Without this the files are in the APK and unreachable: the navigator serves
    // only the asset paths it has been told about.
    servedAssets += "fonts/.*"

    variable(ReaderTypeface.LITERATA, "Literata", 300..700)
    variable(ReaderTypeface.SOURCE_SERIF, "SourceSerif4", 300..700)
    variable(ReaderTypeface.EB_GARAMOND, "EBGaramond", 400..700)
    variable(ReaderTypeface.BITTER, "Bitter", 300..700)
    statics(ReaderTypeface.ATKINSON_HYPERLEGIBLE, "AtkinsonHyperlegible")
}

/**
 * One upright and one italic over a weight range.
 *
 * The range is what `packages/fonts/scripts/build.py` instanced the file down to.
 * Declaring a wider one would ask the renderer to extrapolate weights the file no
 * longer carries.
 */
@OptIn(ExperimentalReadiumApi::class)
private fun EpubNavigatorFragment.Configuration.variable(
    face: ReaderTypeface,
    stem: String,
    weights: IntRange,
) {
    val family = face.cssFamily ?: return
    addFontFamilyDeclaration(FontFamily(family)) {
        addFontFace {
            addSource("fonts/$stem.ttf")
            setFontStyle(FontStyle.NORMAL)
            setFontWeight(weights)
        }
        addFontFace {
            addSource("fonts/$stem-Italic.ttf")
            setFontStyle(FontStyle.ITALIC)
            setFontWeight(weights)
        }
    }
}

/** Four static faces: regular, italic, bold, bold italic. */
@OptIn(ExperimentalReadiumApi::class)
private fun EpubNavigatorFragment.Configuration.statics(face: ReaderTypeface, stem: String) {
    val family = face.cssFamily ?: return
    addFontFamilyDeclaration(FontFamily(family)) {
        addFontFace {
            // Preloaded: this is the accessibility face, and a reader who needs it
            // should not watch it arrive.
            addSource("fonts/$stem-Regular.ttf", preload = true)
            setFontStyle(FontStyle.NORMAL)
            setFontWeight(FontWeight.NORMAL)
        }
        addFontFace {
            addSource("fonts/$stem-Italic.ttf")
            setFontStyle(FontStyle.ITALIC)
            setFontWeight(FontWeight.NORMAL)
        }
        addFontFace {
            addSource("fonts/$stem-Bold.ttf")
            setFontStyle(FontStyle.NORMAL)
            setFontWeight(FontWeight.BOLD)
        }
        addFontFace {
            addSource("fonts/$stem-BoldItalic.ttf")
            setFontStyle(FontStyle.ITALIC)
            setFontWeight(FontWeight.BOLD)
        }
    }
}
