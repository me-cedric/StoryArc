package app.storyarc.feature.epubreader

import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AxisUnit
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import java.text.NumberFormat

// The theme sheet's smaller pieces: a preset card previewing its own colours, the
// reader's own palette as a seventh card, the typeface specimen they share, the
// step-position dots, and the names the domain enums go by on screen.
//
// Split out of `ThemeSheet.kt` because that file had reached 911 lines against this
// project's 800-line cap, so the next section anyone added would have pushed it over —
// and the live preview is that section. iOS's `ThemeSheetParts.swift` is the same split
// on the same boundary, which is why the two files carry the same name.

/**
 * A few words in one face, for a card the size of a postage stamp.
 *
 * Words rather than lorem ipsum: a reader judges a typeface by shapes they know. Two
 * short lines fit a 48dp card and still show ascenders, descenders and a figure,
 * which is most of what distinguishes one serif from another.
 */
@Composable
internal fun Specimen(
    typeface: ReaderTypeface,
    colour: Color,
    modifier: Modifier = Modifier,
    isBold: Boolean = false,
) {
    val family = typeface.fontFamily()

    // Sized in `dp`, so the system text size does not scale it. A specimen is a
    // *picture* of a typeface and the card it sits in is a fixed size: at twice the
    // system text size the words grew and the card clipped them, which is a specimen
    // that shows less of the face the larger the reader needs it.
    val fixed = with(LocalDensity.current) { SPECIMEN_DP.dp.toSp() }

    Column(
        // One picture, and not a sentence a screen reader should read twice per card.
        modifier = modifier.fillMaxWidth().clearAndSetSemantics {},
    ) {
        listOf(R.string.theme_specimen, R.string.theme_specimen_second).forEach { line ->
            Text(
                text = stringResource(line),
                style = MaterialTheme.typography.bodyMedium
                    .copy(fontFamily = family, fontSize = fixed),
                // Always explicit. A variable font's default instance is whatever its
                // `fvar` says, and upstream Bitter's is Thin — a specimen that let the
                // default stand would show a hairline and call it Bitter.
                fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal,
                color = colour,
                maxLines = 1,
            )
        }
    }
}

/**
 * The reader's own palette, as a seventh card in the same grid.
 *
 * Drawn from the same parts as a preset card, in its own colours, for the same
 * reason: a grid of samples reads at a glance and a grid of labels does not. It
 * carries the reader's name for the slot rather than the word "custom", because a
 * slot they named and cannot see the name of is not really theirs.
 */
@Composable
internal fun CustomCard(
    palette: ReaderPalette,
    /** The face in force, since a colour slot has none of its own. */
    typeface: ReaderTypeface,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalStoryArcPalette.current
    val name = palette.name.trim().ifEmpty { stringResource(R.string.theme_page_colour_untitled) }

    Surface(
        modifier = modifier.semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(StoryArcRadius.md),
    ) {
        Column(
            modifier = Modifier
                .selectable(selected = true, role = Role.RadioButton, onClick = onSelect)
                .padding(StoryArcSpace.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
                    .clip(RoundedCornerShape(StoryArcRadius.sm))
                    .background(Color(AndroidColor.parseColor(palette.background)))
                    .border(
                        width = 2.dp,
                        color = tokens.accent,
                        shape = RoundedCornerShape(StoryArcRadius.sm),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Specimen(
                    typeface = typeface,
                    colour = Color(AndroidColor.parseColor(palette.foreground)),
                    modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                )
            }

            Text(
                text = name,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                // The accent measures 2.99 to 1 on this card in light appearance, so
                // the name it carries is text a low-vision reader cannot read.
                color = tokens.textPrimary,
            )
        }
    }
}

/** Three across, which is what `ebook-reader`'s "three by two" means. */
internal const val COLUMNS = 3

/**
 * How big a typeface specimen is drawn, in `dp` rather than `sp`.
 *
 * Fixed on purpose: see the note in `Specimen`.
 */
private const val SPECIMEN_DP = 14

/**
 * A slider's value as a screen reader should say it.
 *
 * The unit comes from the domain, so the two platforms cannot describe the same
 * slider differently. `NumberFormat` rather than `String.format`, because a comma
 * decimal separator is not a detail a French reader should have to work around.
 */
@Composable
internal fun spokenValue(value: Double, unit: AxisUnit?): String {
    val number = remember {
        NumberFormat.getInstance().apply { maximumFractionDigits = 2 }
    }.format(value)
    return when (unit) {
        AxisUnit.MULTIPLE -> stringResource(R.string.theme_axis_value_multiple, number)
        AxisUnit.EM -> stringResource(R.string.theme_axis_value_em, number)
        null -> number
    }
}

/** One preset, previewed in its own colours. */
@Composable
internal fun PresetCard(
    preset: ThemePreset,
    isActive: Boolean,
    isModified: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val sample = ReadingTheme(preset)

    // A tonal card, which is what `native-experience` asks Android for where iOS
    // gets glass. `selectable` rather than `clickable`: six mutually exclusive
    // options are a radio group, and TalkBack then says which one is chosen instead
    // of offering six identical buttons. Merged, so the card speaks as one thing.
    Surface(
        modifier = modifier.semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(StoryArcRadius.md),
    ) {
    Column(
        modifier = Modifier
            .selectable(selected = isActive, role = Role.RadioButton, onClick = onSelect)
            .padding(StoryArcSpace.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(RoundedCornerShape(StoryArcRadius.sm))
                .background(Color(AndroidColor.parseColor(sample.background)))
                .border(
                    width = if (isActive) 2.dp else 1.dp,
                    color = if (isActive) palette.accent else palette.borderSubtle,
                    shape = RoundedCornerShape(StoryArcRadius.sm),
                ),
            contentAlignment = Alignment.Center,
        ) {
            // Real letterforms in the preset's own face and colour.
            // `reading-themes` asks each card to preview "its own colours and
            // typeface", and a stack of grey rules — which is what this was — can
            // show a colour but never a face.
            Specimen(
                typeface = preset.values.typeface,
                colour = Color(AndroidColor.parseColor(sample.foreground)),
                isBold = preset.values.isBold,
                modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
            )

            // A hand-drawn tick, and no elevation change.
            //
            // `design.md`: `Card` has no `selected` parameter and `CardColors` has no
            // selected role — verified by `javap` — so the selected state is drawn here. The
            // nearest Material rule that does exist is the list one: the selected state
            // covers the whole item and single-select uses a radio-button role, which the
            // `selectable` above supplies. Material says card variants differ "on style
            // alone" and reserves an elevation change for pick-up-and-move, so the card does
            // not rise when it is chosen.
            //
            // Decorative: the `selectable` role already tells a screen reader which card is
            // selected, and a second announcement of the same fact is one too many.
            if (isActive) {
                Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(StoryArcSpace.xs)
                        .size(16.dp)
                        .clearAndSetSemantics {},
                )
            }
        }

        Text(
            text = stringResource(preset.labelRes),
            style = MaterialTheme.typography.labelLarge,
            // Weight as well as colour: colour is never the only signal.
            fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal,
            // Not the accent when active: it measures 2.99 to 1 on this card in light
            // appearance, so the chosen card was the one card no one could read.
            color = if (isActive) palette.textPrimary else palette.textSecondary,
        )

        if (isModified) {
            Text(
                text = stringResource(R.string.theme_modified),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )
        }
    }
    }
}

/** Where the size sits on its ladder. */
@Composable
internal fun StepDots(position: Int, count: Int, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.hair, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            Box(
                Modifier
                    .size(if (index == position) 7.dp else 5.dp)
                    .clip(CircleShape)
                    .background(if (index == position) palette.accent else palette.borderSubtle),
            )
        }
    }
}

internal val ThemePreset.labelRes: Int
    get() = when (this) {
        ThemePreset.ORIGINAL -> R.string.theme_preset_original
        ThemePreset.QUIET -> R.string.theme_preset_quiet
        ThemePreset.PAPER -> R.string.theme_preset_paper
        ThemePreset.BOLD -> R.string.theme_preset_bold
        ThemePreset.CALM -> R.string.theme_preset_calm
        ThemePreset.FOCUS -> R.string.theme_preset_focus
    }

internal val ReaderTypeface.labelRes: Int
    get() = when (this) {
        ReaderTypeface.PUBLISHER -> R.string.theme_typeface_publisher
        ReaderTypeface.SERIF -> R.string.theme_typeface_serif
        ReaderTypeface.SANS -> R.string.theme_typeface_sans
        // The bundled families go by their own names, which is how a reader
        // recognises them.
        ReaderTypeface.LITERATA -> R.string.theme_typeface_literata
        ReaderTypeface.SOURCE_SERIF -> R.string.theme_typeface_source_serif
        ReaderTypeface.EB_GARAMOND -> R.string.theme_typeface_eb_garamond
        ReaderTypeface.BITTER -> R.string.theme_typeface_bitter
        ReaderTypeface.ATKINSON_HYPERLEGIBLE -> R.string.theme_typeface_atkinson
    }

internal val ReaderTextAlignment.labelRes: Int
    get() = when (this) {
        ReaderTextAlignment.PUBLISHER -> R.string.theme_alignment_publisher
        ReaderTextAlignment.LEFT -> R.string.theme_alignment_left
        ReaderTextAlignment.JUSTIFIED -> R.string.theme_alignment_justified
    }

internal val ThemeAxis.labelRes: Int
    get() = when (this) {
        ThemeAxis.FONT_SIZE -> R.string.theme_axis_font_size
        ThemeAxis.FONT_FAMILY -> R.string.theme_axis_font_family
        ThemeAxis.BOLD_TEXT -> R.string.theme_axis_bold_text
        ThemeAxis.LINE_SPACING -> R.string.theme_axis_line_spacing
        ThemeAxis.CHARACTER_SPACING -> R.string.theme_axis_character_spacing
        ThemeAxis.WORD_SPACING -> R.string.theme_axis_word_spacing
        ThemeAxis.PARAGRAPH_SPACING -> R.string.theme_axis_paragraph_spacing
        ThemeAxis.MARGINS -> R.string.theme_axis_margins
        ThemeAxis.TEXT_ALIGNMENT -> R.string.theme_axis_text_alignment
        ThemeAxis.HYPHENATION -> R.string.theme_axis_hyphenation
    }
