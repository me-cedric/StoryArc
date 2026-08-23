package app.storyarc.core.designsystem.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import app.storyarc.core.designsystem.tokens.StoryArcType

/**
 * The type scale from `packages/design-tokens/tokens/typography.json`, mapped
 * onto Material's slots.
 *
 * System sans everywhere, because that is what makes the chrome read as stock.
 * The single serif moment — `display`, used on publication titles — is applied
 * per-call rather than through a Material slot, so it stays deliberate.
 */
private fun sans(size: androidx.compose.ui.unit.TextUnit, line: androidx.compose.ui.unit.TextUnit, weight: FontWeight) =
    TextStyle(fontFamily = FontFamily.Default, fontSize = size, lineHeight = line, fontWeight = weight)

internal val StoryArcTypography = Typography(
    displayLarge = sans(StoryArcType.displaySize, StoryArcType.displayLineHeight, FontWeight.SemiBold),
    headlineLarge = sans(StoryArcType.title1Size, StoryArcType.title1LineHeight, FontWeight.Bold),
    headlineMedium = sans(StoryArcType.title2Size, StoryArcType.title2LineHeight, FontWeight.Bold),
    headlineSmall = sans(StoryArcType.title3Size, StoryArcType.title3LineHeight, FontWeight.SemiBold),
    titleMedium = sans(StoryArcType.headlineSize, StoryArcType.headlineLineHeight, FontWeight.SemiBold),
    bodyLarge = sans(StoryArcType.bodySize, StoryArcType.bodyLineHeight, FontWeight.Normal),
    bodyMedium = sans(StoryArcType.calloutSize, StoryArcType.calloutLineHeight, FontWeight.Normal),
    bodySmall = sans(StoryArcType.subheadlineSize, StoryArcType.subheadlineLineHeight, FontWeight.Normal),
    labelLarge = sans(StoryArcType.footnoteSize, StoryArcType.footnoteLineHeight, FontWeight.Medium),
    labelMedium = sans(StoryArcType.captionSize, StoryArcType.captionLineHeight, FontWeight.Normal),
    labelSmall = sans(StoryArcType.caption2Size, StoryArcType.caption2LineHeight, FontWeight.Normal),
)

/** The serif face used only for publication titles and series headers. */
val EditorialFontFamily: FontFamily = FontFamily.Serif
