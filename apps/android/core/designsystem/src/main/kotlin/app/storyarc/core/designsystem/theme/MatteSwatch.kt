package app.storyarc.core.designsystem.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.R
import app.storyarc.core.designsystem.control.MIN_TOUCH_TARGET
import app.storyarc.core.model.SUGGESTED_BACKGROUND_NAMES

/**
 * One colour a comic page can be read against: a disc in [hex], ringed in the accent when
 * it is the active one, inside a [MIN_TOUCH_TARGET] radio target.
 *
 * Black stands for no colour, which is what a comic is read against by default. The reader's
 * adjustments sheet and the reading defaults draw the same swatch; [description] is the
 * caller's because each names "no colour" from its own catalogue.
 */
@Composable
fun MatteSwatch(
    hex: String?,
    isActive: Boolean,
    description: String,
    // shortcut: the two callers draw the disc 30 dp and 32 dp; one size when a snapshot pass
    // can take the pixel change.
    diameter: Dp = 30.dp,
    onChoose: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Box(
        modifier = Modifier
            .size(MIN_TOUCH_TARGET)
            .selectable(selected = isActive, role = Role.RadioButton, onClick = onChoose)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(diameter)
                .clip(CircleShape)
                .background(hexColour(hex) ?: Color.Black)
                .border(
                    width = if (isActive) 3.dp else 1.dp,
                    color = if (isActive) palette.accent else palette.borderSubtle,
                    shape = CircleShape,
                ),
        )
    }
}

/**
 * The name of a suggested background, or a template that reads its hex if the list ever
 * gains one the catalogue has no word for -- never a bare code, which TalkBack reads one
 * character at a time. Format the result with [hex] so the template has its argument.
 *
 * Not `@Composable`: it reads no composition, it only maps a hex to a resource id, so a
 * semantics test can ask the same question the screen asks.
 */
fun matteNameRes(hex: String): Int = when (SUGGESTED_BACKGROUND_NAMES[hex.uppercase()]) {
    "white" -> R.string.matte_white
    "cream" -> R.string.matte_cream
    "sepia" -> R.string.matte_sepia
    "sage" -> R.string.matte_sage
    "sky" -> R.string.matte_sky
    "charcoal" -> R.string.matte_charcoal
    "navy" -> R.string.matte_navy
    "trueBlack" -> R.string.matte_trueblack
    else -> R.string.matte_swatch
}
