package app.storyarc.core.designsystem.theme

import androidx.compose.ui.graphics.Color
import app.storyarc.core.model.HighlightColour

/**
 * What the colour looks like on a page.
 *
 * Fixed hues rather than palette tokens: a highlight is ink a reader chose, and one that changed
 * colour when they changed theme would stop meaning what they meant by it.
 *
 * Here rather than in a reader, because both readers draw it. The EPUB navigator composites it
 * over reflowed text and the PDF reader paints it over a rasterised page, and a highlight that
 * was two different yellows depending on the format would be a defect one reader could see in
 * one library.
 *
 * iOS's `swatch` is the same five.
 */
val HighlightColour.swatch: Color
    get() = when (this) {
        HighlightColour.YELLOW -> Color(0xFFFFD940)
        HighlightColour.GREEN -> Color(0xFF73D973)
        HighlightColour.BLUE -> Color(0xFF66B8FF)
        HighlightColour.PINK -> Color(0xFFFF8CBF)
        HighlightColour.PURPLE -> Color(0xFFB88CFF)
    }
