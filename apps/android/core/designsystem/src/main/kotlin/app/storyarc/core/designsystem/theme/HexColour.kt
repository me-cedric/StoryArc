package app.storyarc.core.designsystem.theme

import androidx.compose.ui.graphics.Color

/**
 * A `#rrggbb` string as a colour, or null when [hex] is not one.
 *
 * Null rather than a fallback, so each caller keeps its own: black behind a comic page,
 * `Unspecified` on a theme sample, white on an end-of-book button. The domain and the tokens
 * both speak hex — a stored colour has to survive a round trip — and this is the one place
 * the design system turns one into a `Color`.
 */
fun hexColour(hex: String?): Color? {
    val text = hex?.removePrefix("#") ?: return null
    if (text.length != 6) return null
    val value = text.toLongOrNull(16) ?: return null
    return Color(0xFF000000L or value)
}
