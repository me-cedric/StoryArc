package app.storyarc.feature.settings

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcDuration
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlinx.coroutines.delay

/**
 * How long a highlight stays lit before it fades.
 *
 * Long enough to be seen by someone whose eyes are still on the search field they came
 * from, short enough that it is gone before it becomes part of the screen. A highlight that
 * never fades stops meaning "here" and starts meaning "selected", which is a different
 * claim and a wrong one.
 */
private const val HIGHLIGHT_DWELL_MILLIS = 2_000L

/** Enough tint to find the row by, not enough to fight the text on top of it. */
private const val HIGHLIGHT_ALPHA = 0.30f

/**
 * Marks this row as the one a search result points at.
 *
 * `settings-and-about` asks a search result to navigate "and highlight" what it matched.
 * Two things make that true and neither is enough alone: the row has to be *on screen*,
 * which is what [bringIntoViewRequester] does, and it has to be *pointed at*, which is the
 * tint. A tint below the fold highlights nothing, and a scroll with no tint leaves a reader
 * looking at a list.
 *
 * Applied to whatever the setting *is*: one row for a switch, a whole column for the
 * reading defaults. Both are one setting to a reader, and the tint should cover what they
 * came to find rather than the first line of it.
 */
@Composable
internal fun Modifier.settingsHighlight(
    anchor: SettingsAnchor,
    highlight: SettingsAnchor?,
): Modifier {
    val palette = LocalStoryArcPalette.current
    val requester = remember { BringIntoViewRequester() }
    var lit by remember { mutableStateOf(false) }

    val alpha by animateFloatAsState(
        targetValue = if (lit) HIGHLIGHT_ALPHA else 0f,
        animationSpec = tween(durationMillis = StoryArcDuration.chromeFade),
        label = "settingsHighlight",
    )

    LaunchedEffect(highlight, anchor) {
        if (highlight != anchor) {
            lit = false
            return@LaunchedEffect
        }
        lit = true
        requester.bringIntoView()
        delay(HIGHLIGHT_DWELL_MILLIS)
        lit = false
    }

    return this
        .bringIntoViewRequester(requester)
        .background(
            color = palette.accentMuted.copy(alpha = alpha),
            shape = RoundedCornerShape(StoryArcRadius.sm),
        )
        // Inside the tint rather than outside it, so the highlight has a margin around the
        // text instead of ending on the first and last glyph.
        .padding(StoryArcSpace.xs)
}
