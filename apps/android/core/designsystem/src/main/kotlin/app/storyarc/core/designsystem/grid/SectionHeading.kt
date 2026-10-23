package app.storyarc.core.designsystem.grid

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * One heading over its part of a shelf: the library's sections and the Downloads groups.
 *
 * On `surfaceOverlay` — the token the design system declares for chrome that has to be
 * opaque — rather than on the canvas, because a wall of covers slides under this: a
 * translucent band would show the artwork of whatever happened to be passing beneath the
 * words. A hairline separates it from the covers below.
 *
 * One line, even at the largest text size. A three-line heading pinned to the top of the
 * shelf would take more of the screen than the section it names. iOS's `SectionHeading` makes
 * both of the same choices for both of the same reasons.
 *
 * @param textPadding how far the words are inset from the band's own edges. The band fills the
 *   width its lazy list gives it, which is the list's width less its content padding — a
 *   gutter at the start, and a gutter or the rail's width at the end. So a grid insets
 *   nothing here, because that padding already holds its words off the edge, and a list
 *   passes the inset its rows set for themselves.
 */
@Composable
fun SectionHeading(title: String, textPadding: Dp = 0.dp) {
    val palette = LocalStoryArcPalette.current
    Column(modifier = Modifier.fillMaxWidth().background(palette.surfaceOverlay)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = StoryArcSpace.sm, horizontal = textPadding),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(StoryArcSpace.hair)
                .background(palette.borderSubtle),
        )
    }
}
