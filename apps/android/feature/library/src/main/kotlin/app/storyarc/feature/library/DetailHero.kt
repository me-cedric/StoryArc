package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.EditorialFontFamily
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * The widest the primary action is drawn when it sits beside the cover.
 *
 * A filled button is emphasised by being the one filled thing on the screen, not by being
 * long. Material's own guidance caps a button's text at a readable measure, and 800 dp of
 * landscape phone offers three times that.
 */
private val ACTION_WIDTH = 320.dp

/**
 * The cover, over the colour the cover gave the page.
 *
 * `publication-detail`: "the cover is the largest thing on it, shown whole rather than
 * cropped", and "the background carries a colour derived from that cover, so the screen
 * belongs to the book" — while "the cover itself is not tinted, recoloured or dimmed by
 * it". So the wash is a container the artwork sits *in*, never a layer over it.
 *
 * The container is where this page gets its emphasis, and it gets it Material's way rather
 * than iOS's. M3 Expressive's first tactic is to break from the surrounding shape style to
 * draw attention; the direction's divergence register records that as the Android answer to
 * iOS's prominent glass button, "because it emphasises without tinting artwork". So the
 * hero takes `shapes.extraLarge` while every other container on the page takes `medium` or
 * `large`, and no component on the page is emphasised with colour at all.
 *
 * The cover keeps its own 4 dp radius inside that. `design.md` §4: "a comic cover is
 * printed stock. Rounding it like an app icon reads as wrong."
 */
@Composable
internal fun DetailHero(
    publication: Publication,
    cover: Bitmap?,
    accent: DetailAccent?,
    /**
     * How the container arranges itself in the room the page has.
     *
     * On a short window the cover and the action share a row rather than stacking — see
     * [DetailHeroLayout], which carries the window that had no way to open a book at all.
     */
    layout: DetailHeroLayout,
    modifier: Modifier = Modifier,
    /**
     * The primary action, drawn inside the container rather than under it.
     *
     * Not a layout preference: `CoverAccent` guarantees the accent clears the 3:1 floor
     * **against the wash**, which is the pair it was adjusted for. A filled action drawn on
     * the page's own ground would be a colour checked against one background and shown on
     * another — the exact "used raw" failure the delta forbids. Containing the two together
     * is also M3 Expressive's second tactic, and it is what makes the one important control
     * on the screen look important without tinting the artwork.
     */
    action: @Composable () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    // The page renders correctly with no accent and adopts one when it arrives. Animated
    // through the theme's own scheme rather than a `tween`: the direction asks custom
    // animation to consume `MaterialTheme.motionScheme`, whose speed tokens are
    // device-aware in a way a fixed duration is not — and it is what keeps the arrival
    // from being a flash.
    val wash by animateColorAsState(
        targetValue = accent?.wash ?: palette.surfaceSunken,
        animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
        label = "cover wash",
    )

    Surface(
        color = wash,
        shape = MaterialTheme.shapes.extraLarge,
        modifier = modifier.fillMaxWidth(),
    ) {
        if (layout.isSideBySide) {
            // The artwork and the action share the width that was being spent on empty wash
            // — 800 dp of it, around a 96 dp cover. Centred as a pair and the action bounded,
            // because a button stretched across 530 dp of landscape phone is not a button
            // being emphasised, it is a button nobody drew.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement =
                    Arrangement.spacedBy(StoryArcSpace.xl, Alignment.CenterHorizontally),
                modifier = Modifier.fillMaxWidth().padding(layout.padding),
            ) {
                DetailCover(publication = publication, cover = cover, height = layout.coverHeight)
                Box(modifier = Modifier.weight(1f, fill = false).widthIn(max = ACTION_WIDTH)) {
                    action()
                }
            }
            return@Surface
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
            modifier = Modifier.fillMaxWidth().padding(layout.padding),
        ) {
            DetailCover(publication = publication, cover = cover, height = layout.coverHeight)
            action()
        }
    }
}

/**
 * The artwork, whole.
 *
 * `ContentScale.Fit` rather than `Crop`: the grid crops because a wall of covers has to
 * line up, and this page exists so the reader can look at one. What is left over
 * letterboxes onto `surfaceSunken`, as `design.md` §4 requires everywhere art meets a cell.
 *
 * Decorative to a screen reader — the title is read out of the app bar, and announcing it
 * twice reads as a stutter.
 */
@Composable
private fun DetailCover(publication: Publication, cover: Bitmap?, height: Dp) {
    val palette = LocalStoryArcPalette.current
    Surface(
        color = palette.surfaceSunken,
        shape = RoundedCornerShape(StoryArcRadius.cover),
        modifier = Modifier
            .heightIn(max = height)
            // Height first, so the bound above decides and the width follows the printed
            // proportion — the other way round the ratio would fight the cap and win.
            .aspectRatio(2f / 3f, matchHeightConstraintsFirst = true)
            .clearAndSetSemantics {},
    ) {
        if (cover != null) {
            Image(
                bitmap = cover.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // The app's own placeholder, and the title is never rendered over an image
            // that failed to load — the delta says so, and this is a surface with nothing
            // underneath it rather than a caption on a broken one.
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm, Alignment.CenterVertically),
                modifier = Modifier.fillMaxSize().padding(StoryArcSpace.lg),
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.MenuBook,
                    contentDescription = null,
                    tint = palette.textTertiary,
                )
                Text(
                    text = publication.format.displayName,
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textTertiary,
                )
            }
        }
    }
}

/**
 * Title and subtitle for the top app bar, as one block.
 *
 * The delta wants the title, the series and the year to read as one object. Material's
 * flexible app bars grew a subtitle slot for exactly that, so the block *is* the bar's
 * title and subtitle rather than a stack repeated below the cover — and it collapses onto
 * the artwork as the reader scrolls, which is what `LargeFlexibleTopAppBar` is for.
 *
 * The serif is StoryArc's one deliberate exception to "Material slots carry Material
 * sizes": the direction keeps the `editorial` role and gives it publication titles.
 */
@Composable
internal fun DetailTitle(publication: Publication) {
    Text(
        text = publication.displayTitle,
        // No `style`: the flexible bar supplies the expanded and collapsed sizes itself and
        // interpolates between them, so naming one here would pin the title at whichever
        // size was written down and lose the collapse. Only the face is StoryArc's.
        fontFamily = EditorialFontFamily,
        fontWeight = FontWeight.SemiBold,
    )
}

/**
 * Series, number and year — and nothing at all when the publication declares none.
 *
 * "Those lines are absent rather than shown empty or filled with a placeholder", and "the
 * page's composition holds together with only a cover and a title". Joined with a middle
 * dot rather than translated into a sentence: a series name, an issue number and a year
 * read the same way in every language this app speaks.
 */
@Composable
internal fun DetailSubtitle(publication: Publication) {
    val palette = LocalStoryArcPalette.current
    val parts = listOfNotNull(
        publication.series?.takeIf { it.isNotBlank() },
        publication.number?.takeIf { it.isNotBlank() }?.let { "#$it" },
        publication.year?.toString(),
    )
    if (parts.isEmpty()) return
    Text(
        text = parts.joinToString(" · "),
        style = MaterialTheme.typography.bodyMedium,
        color = palette.textSecondary,
    )
}
