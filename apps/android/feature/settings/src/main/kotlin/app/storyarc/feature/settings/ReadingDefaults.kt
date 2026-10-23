package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.MatteSwatch
import app.storyarc.core.designsystem.theme.matteNameRes
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.model.values
import app.storyarc.core.persistence.ReaderPreferences

/**
 * What a series never opened before is read with.
 *
 * `settings-and-about`: "it applies to publications opened from then on and does not
 * overwrite a per-series choice already made". That second clause needs no code here —
 * [ShelfMemory.settingDefault] writes to a different map than the per-shelf entries, so it
 * *cannot* reach one. The guarantee is structural rather than careful.
 *
 * Two scopes, because `reading-themes` gives comics and reflowable text separate defaults
 * and the spec means it: a reader who wants cream paper for novels may well want black
 * behind a comic.
 *
 * Names rather than the reader's preset *cards*. A card previews a theme in its own
 * colours and typeface, which is worth the space when the page is visible behind it and is
 * six swatches of decoration in a settings list.
 */
@Composable
internal fun ReadingDefaults(
    store: ReaderPreferences,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    // Kept as Compose state and set again after each save, the way iOS's `@State memory`
    // does (`ReadingDefaults.swift`). Reading `store.themes()` as a plain value compiled
    // and drew, but a tap on a row or a swatch called `store.save` and nothing here
    // observed it, so the radio button and the matte ring never moved until the screen
    // recomposed for an unrelated reason.
    var memory by remember { mutableStateOf(store.themes()) }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        Text(
            text = stringResource(R.string.reading_defaults),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.reading_defaults_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )

        ThemeScope.entries.forEach { scope ->
            // `reading-themes`: a comic has no typography for a preset to change, so a
            // preset picker offered nothing a comic reader honoured — the fixed-layout
            // scope keeps only its own colour, below.
            if (scope == ThemeScope.REFLOWABLE) {
                ScopeDefaults(
                    scope = scope,
                    memory = memory,
                    store = store,
                    onSaved = { memory = it },
                )
            }
            if (scope == ThemeScope.FIXED_LAYOUT) {
                ComicMatte(memory = memory, store = store, onSaved = { memory = it })
            }
        }
    }
}

/**
 * The colour behind a comic page.
 *
 * `reading-themes`: a custom background "applies to the area around the page and not to the
 * page itself, because tinting artwork is not a reading preference". A comic has no
 * typography for a preset to change, so what a preset offers it is only its paper colour —
 * and that is not what a preset means. This is the colour, on its own.
 *
 * Swatches only. The reader's own picker, with its sliders and its contrast refusal, lives
 * in the *reader*, where the page is visible behind it and a choice can be judged. Here
 * there is nothing to judge it against, and the suggested backgrounds all clear AAA
 * already, so a picker would offer a refusal path with no way to see why.
 */
@Composable
private fun ComicMatte(memory: ShelfMemory, store: ReaderPreferences, onSaved: (ShelfMemory) -> Unit) {
    val palette = LocalStoryArcPalette.current
    val current = memory.default(ThemeScope.FIXED_LAYOUT).theme.custom?.background

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
        Text(
            text = stringResource(R.string.reading_matte),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
            modifier = Modifier.padding(top = StoryArcSpace.sm),
        )
        Text(
            text = stringResource(R.string.reading_matte_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )

        // Wrapping, not a fixed row. Nine 48dp targets plus their gaps need 496dp and
        // the narrowest supported screen is 320dp, so a plain Row clipped the last two
        // swatches off the edge — where a reader could see them and not reach them.
        FlowRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = StoryArcSpace.xs),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            // Black first and unlabelled as a swatch of its own: it is the default, and
            // "none" has to be reachable or a reader who tries a colour is stuck with one.
            // The colour's name, not its hex. TalkBack read "Colour #E8EFE6" one character
            // at a time, which is not a colour a reader can pick out of a row of eight.
            MatteSwatch(
                hex = null,
                isActive = current == null,
                description = stringResource(R.string.reading_matte_none),
                diameter = 32.dp,
            ) { choose(null, store, memory, onSaved) }
            SUGGESTED_BACKGROUNDS.forEach { hex ->
                MatteSwatch(
                    hex = hex,
                    isActive = current?.equals(hex, ignoreCase = true) == true,
                    description = stringResource(matteNameRes(hex), hex),
                    diameter = 32.dp,
                ) { choose(hex, store, memory, onSaved) }
            }
        }
    }
}

/** Stores [hex] as the comic default and hands the saved memory back. */
private fun choose(hex: String?, store: ReaderPreferences, memory: ShelfMemory, onSaved: (ShelfMemory) -> Unit) {
    val existing = memory.default(ThemeScope.FIXED_LAYOUT)
    val updated = store.themes().settingDefault(
        existing.copy(theme = matting(hex, existing.theme)),
        ThemeScope.FIXED_LAYOUT,
    )
    store.save(updated)
    onSaved(updated)
}

/**
 * The comic default's theme with the matte [hex] in force, or with no matte.
 *
 * The comic reader reads only the matte. A comic default stored as Original, from before this
 * scope lost its preset picker, refuses every palette, so the matte goes over the built-in
 * preset instead. Named by its hex, not by the localised announcement: what is stored must not
 * depend on the language it was set in.
 */
internal fun matting(hex: String?, theme: ReadingTheme): ReadingTheme {
    if (hex == null) return theme.discardingCustomColours()
    val base = if (theme.preset.keepsPublisherStyles) ReadingTheme() else theme
    return base.adopting(ReaderPalette.derived(hex, hex))
}

/**
 * The chosen preset and its typography, kept beside the rest of the stored default.
 *
 * `reading-themes`, *Changing the global default*: a fresh `ShelfSettings(theme, values)`
 * here put the transition, the adjustments and the matte back to their built-in values on
 * every change, because a value this function never named still has to come from
 * somewhere, and a bare constructor names the built-in one.
 *
 * A plain function beside the composable, because no JVM test can press a row inside
 * `ScopeDefaults` and this is what `ReadingDefaultsChoosingTest` proves the behaviour over.
 * iOS splits it the same way, into `ReadingDefaults.choosing(_:from:)`.
 */
internal fun choosingPreset(preset: ThemePreset, existing: ShelfSettings): ShelfSettings =
    existing.copy(theme = ReadingTheme(preset), values = preset.values)

@Composable
private fun ScopeDefaults(
    scope: ThemeScope,
    memory: ShelfMemory,
    store: ReaderPreferences,
    onSaved: (ShelfMemory) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val current = memory.default(scope).theme.preset

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
        Text(
            text = stringResource(scope.labelRes),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
            modifier = Modifier.padding(top = StoryArcSpace.sm),
        )

        ThemePreset.entries.forEach { preset ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectableRow(selected = current == preset) {
                        val stored = choosingPreset(preset, memory.default(scope))
                        val updated = store.themes().settingDefault(stored, scope)
                        store.save(updated)
                        onSaved(updated)
                    }
                    .padding(vertical = StoryArcSpace.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = current == preset, onClick = null)
                Text(
                    text = stringResource(preset.labelRes),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                    modifier = Modifier.padding(start = StoryArcSpace.sm),
                )
            }
        }
    }
}

/** How the two scopes are named on screen. */
private val ThemeScope.labelRes: Int
    get() = when (this) {
        ThemeScope.REFLOWABLE -> R.string.reading_defaults_reflowable
        ThemeScope.FIXED_LAYOUT -> R.string.reading_defaults_fixed
    }

/**
 * How the six presets are named here.
 *
 * A third copy of this list, after the two readers'. The alternative is a shared string
 * module for six words, and `reading-themes` names them in the spec rather than in code —
 * so the duplication is of a translation, not of a decision.
 */
internal val ThemePreset.labelRes: Int
    get() = when (this) {
        ThemePreset.ORIGINAL -> R.string.preset_original
        ThemePreset.QUIET -> R.string.preset_quiet
        ThemePreset.PAPER -> R.string.preset_paper
        ThemePreset.BOLD -> R.string.preset_bold
        ThemePreset.CALM -> R.string.preset_calm
        ThemePreset.FOCUS -> R.string.preset_focus
    }
