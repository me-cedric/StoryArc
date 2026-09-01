package app.storyarc.feature.epubreader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import kotlinx.coroutines.launch
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.STEPS_PER_AXIS
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.unit
import app.storyarc.core.model.value
import app.storyarc.core.model.values
import kotlin.math.roundToInt

/**
 * The reading-theme sheet.
 *
 * `ebook-reader` and `reading-themes` between them ask for a preset grid, a stepped
 * font size with a visible position, and — the part that is easy to skip — an axis
 * that cannot reach the page shown "unavailable with a one-line reason and a single
 * action that turns publisher styles off". Not hidden, and not a live control that
 * does nothing.
 *
 * The fine axes — line, character, word and paragraph spacing, margins, alignment,
 * custom background — are Phase 3.5 and 3.7 of the change and are not here yet.
 * What is here is the first level the spec describes. iOS's `ThemeSheet` is the same
 * sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ThemeSheet(
    theme: ReadingTheme,
    values: ThemeValues,
    onAdopt: (ThemePreset) -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    /** Opens level two: the axes, on a destination of their own. */
    onCustomise: () -> Unit,
    /**
     * The sheet this is drawn in, so the header row can toggle its height.
     *
     * Null in a preview, which has no sheet — the header then draws its name and nothing
     * else, which is what it did before Material asked for the toggle.
     */
    sheetState: SheetState? = null,
    modifier: Modifier = Modifier,
    /** The chapter the reader is in, for the live preview to name. */
    chapter: String? = null,
    /**
     * Words from where the reader is, read once when the sheet opens. Empty until the
     * resource comes back, and empty for good on a publication it cannot be read from --
     * the preview shows its sample paragraph in both cases.
     */
    excerpt: String = "",
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
    ) {
        // First, because it is the thing every control below it changes.
        ThemePreview(theme = theme, values = values, title = chapter, excerpt = excerpt)

        HeightToggleHeader(sheetState)

        // Three by two, each card in its own colours. `ebook-reader`: the grid
        // previews "each preset in its own colours — six samples, not six labels".
        //
        // Rows rather than a `LazyVerticalGrid`: there are six or seven known items and
        // this is already inside a scrolling column, so a lazy grid buys nothing and
        // costs a *fixed height* — which at twice the system text size clipped the
        // labels off the bottom of every card. Rows take the height their content needs.
        val cards: List<@Composable (Modifier) -> Unit> = buildList {
            ThemePreset.entries.forEach { preset ->
                add { cardModifier ->
                    PresetCard(
                        preset = preset,
                        isActive = theme.preset == preset && !theme.isCustom,
                        isModified = theme.preset == preset && theme.isModified,
                        onSelect = { onAdopt(preset) },
                        modifier = cardModifier,
                    )
                }
            }
            // The seventh slot, present only once the reader has made one.
            // `reading-themes` puts it "alongside the six presets rather than
            // overwriting one", so it is a seventh card and not a replaced one.
            theme.custom?.let { custom ->
                add { cardModifier ->
                    CustomCard(
                        palette = custom,
                        typeface = values.typeface,
                        onSelect = { onAdoptColours(custom) },
                        modifier = cardModifier,
                    )
                }
            }
        }

        cards.chunked(COLUMNS).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                row.forEach { card -> card(Modifier.weight(1f)) }
                // A short last row keeps its cards the same width as a full one.
                repeat(COLUMNS - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }

        // The one action on level one, and the reason level one is only presets.
        //
        // `ebook-reader`: "one action, given equal prominence to the grid, opens the axes".
        // A filled button across the full width, so it reads as the grid's peer rather than
        // as a footnote under it — a reader who came to nudge line spacing has to be able to
        // see where that lives without having learnt it first.
        Button(
            onClick = onCustomise,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(
                imageVector = Icons.Filled.Tune,
                contentDescription = null,
                modifier = Modifier.padding(end = StoryArcSpace.xs),
            )
            Text(stringResource(R.string.theme_customise))
        }
    }
}

/**
 * The theme sheet, in the platform's own modal bottom sheet.
 *
 * `native-experience` wants the sheet to look like the platform's; iOS gets a
 * detented sheet on Liquid Glass and Android gets this.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ThemeBottomSheet(
    theme: ReadingTheme,
    values: ThemeValues,
    onAdopt: (ThemePreset) -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    /** Opens level two: the axes, on a destination of their own. */
    onCustomise: () -> Unit,
    onDismiss: () -> Unit,
    chapter: String? = null,
    excerpt: String = "",
) {
    // `rememberModalBottomSheetState` is deprecated in 1.5.0-alpha26 with an exact
    // `replaceWith` pointing here: `rememberBottomSheetState(initialValue, enabledValues,
    // confirmValueChange)`. Verified by `javap` over `material3-1.5.0-alpha26.aar` rather than
    // trusted from the documentation.
    //
    // **`enabledValues` is now an explicit decision.** Since alpha21 the `PartiallyExpanded`
    // anchor is no longer removed for you, so a sheet that says nothing gets all three. Level
    // one wants all three: it opens at Material's 50% cap, expands to show the seventh card
    // and the action under the grid, and hides. That is what makes it multi-height, and what
    // makes the header toggle below something Material actually requires.
    val sheetState = rememberBottomSheetState(
        initialValue = SheetValue.PartiallyExpanded,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.PartiallyExpanded, SheetValue.Expanded),
    )

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        ThemeSheet(
            sheetState = sheetState,
            theme = theme,
            values = values,
            onAdopt = onAdopt,
            onAdoptColours = onAdoptColours,
            onCustomise = onCustomise,
            chapter = chapter,
            excerpt = excerpt,
        )
    }
}

/**
 * The sheet's name, and the single-pointer way to change its height.
 *
 * **This fills a gap that is Material's.** Material says "selecting the drag handle should
 * toggle through preset heights" and specifies a Space/Enter contract for it — and
 * `BottomSheetDefaults.DragHandle` has **no** `onClick`. There are zero `clickable` calls in
 * the whole sheet implementation, verified by reading it rather than assumed. So a
 * multi-height sheet owes a hand-built alternative that Material explicitly requires, and
 * level one is multi-height: it opens partially expanded and expands.
 *
 * The header row is where it goes. It is already the width of the sheet, it already carries
 * the sheet's name, and a whole row is well past the platform's minimum touch target — which
 * a 32×4dp handle is not. `Role.Button` with a state description is what gives a screen reader
 * the Space/Enter contract the handle was supposed to have.
 *
 * Delete this the day `DragHandle` takes an `onClick`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HeightToggleHeader(sheetState: SheetState?, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    val scope = rememberCoroutineScope()
    val isExpanded = sheetState?.currentValue == SheetValue.Expanded
    val action = stringResource(
        if (isExpanded) R.string.theme_sheet_collapse else R.string.theme_sheet_expand,
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (sheetState == null) {
                    Modifier
                } else {
                    Modifier
                        .clickable {
                            scope.launch {
                                if (isExpanded) sheetState.partialExpand() else sheetState.expand()
                            }
                        }
                        .semantics {
                            role = Role.Button
                            stateDescription = action
                        }
                },
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.theme_presets),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        if (sheetState != null) {
            Icon(
                imageVector = if (isExpanded) {
                    Icons.Filled.KeyboardArrowDown
                } else {
                    Icons.Filled.KeyboardArrowUp
                },
                // The row carries the name and the state; a second announcement of the
                // same fact is one too many.
                contentDescription = null,
                tint = palette.textSecondary,
            )
        }
    }
}
