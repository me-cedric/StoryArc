package app.storyarc.core.designsystem.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.FontFamily

/**
 * Material's own type scale, unmodified.
 *
 * **This deliberately contradicts [docs/design.md]'s implication that StoryArc's eleven
 * type roles map one-to-one onto both platforms.** They do not, and the mapping was the
 * defect: this file used to pour iOS's numbers into Material's slots — `displayLarge` at
 * 34/41 where Material says 57/64, `bodyLarge` at 17/22 where Material says 16/24 — while
 * `titleLarge`, `displayMedium` and `displaySmall` were left unset and fell through to
 * Material's defaults. Three slots in Material's scale, eight in iOS's, inside one theme.
 *
 * A type scale is a platform artifact. Material slots carry Material sizes, the same way
 * iOS's chrome carries 17 pt body, and a reader who knows what an Android app looks like
 * gets one. The practical consequence is the one the revamp needs: a 34 sp `displayLarge`
 * cannot carry a very large title, and 57 sp can.
 *
 * Nothing is spelled out below because Material already spells it out, and a scale written
 * in two places drifts. `Typography()` is the M3 baseline in full, including the Expressive
 * `*Emphasized` styles — which are how a section header gains weight here, rather than by
 * bolding a slot that Material defines as regular.
 *
 * The tokens in `StoryArcType` are unaffected and still describe the product's roles; what
 * stopped is their being routed through Material's slots. StoryArc's single serif moment
 * is [EditorialFontFamily] below, applied per call, so it stays deliberate.
 */
internal val StoryArcTypography = Typography()

/** The serif face used only for publication titles and series headers. */
val EditorialFontFamily: FontFamily = FontFamily.Serif
