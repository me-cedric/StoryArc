package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import app.storyarc.core.model.SUGGESTED_BACKGROUND_NAMES
import app.storyarc.core.model.ReaderPalette
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
    // Read once per composition of this screen. The reader owns these while it is open;
    // here nothing else is writing them.
    val memory = store.themes()

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
            ScopeDefaults(scope = scope, memory = memory, store = store)
            if (scope == ThemeScope.FIXED_LAYOUT) {
                ComicMatte(memory = memory, store = store)
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
private fun ComicMatte(memory: ShelfMemory, store: ReaderPreferences) {
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
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            // Black first and unlabelled as a swatch of its own: it is the default, and
            // "none" has to be reachable or a reader who tries a colour is stuck with one.
            MatteSwatch(hex = null, isActive = current == null, store = store, memory = memory)
            SUGGESTED_BACKGROUNDS.forEach { hex ->
                MatteSwatch(
                    hex = hex,
                    isActive = current?.equals(hex, ignoreCase = true) == true,
                    store = store,
                    memory = memory,
                )
            }
        }
    }
}

@Composable
private fun MatteSwatch(
    hex: String?,
    isActive: Boolean,
    store: ReaderPreferences,
    memory: ShelfMemory,
) {
    val palette = LocalStoryArcPalette.current
    // The colour's name, not its hex. TalkBack read "Colour #E8EFE6" one character at a
    // time, which is not a colour a reader can pick out of a row of eight.
    val description = hex?.let { stringResource(matteNameRes(it)) }
        ?: stringResource(R.string.reading_matte_none)

    Box(
        // 48dp for the finger, 32dp for the eye. The swatch was 32dp both ways, and a
        // 32dp target is below every platform minimum — including the one Compose
        // enforces on its own controls.
        modifier = Modifier
            .size(48.dp)
            .selectable(
                selected = isActive,
                role = Role.RadioButton,
                onClick = {
                    val existing = memory.default(ThemeScope.FIXED_LAYOUT)
                    val theme = existing.theme.let { current ->
                        if (hex == null) {
                            current.discardingCustomColours()
                        } else {
                            // Named by its hex, not by the localised announcement: what
                            // is stored must not depend on the language it was set in.
                            current.adopting(ReaderPalette.derived(hex, hex))
                        }
                    }
                    store.save(
                        store.themes().settingDefault(
                            existing.copy(theme = theme),
                            ThemeScope.FIXED_LAYOUT,
                        ),
                    )
                },
            )
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(matteSwatchColour(hex))
                .border(
                    width = if (isActive) 3.dp else 1.dp,
                    color = if (isActive) palette.accent else palette.borderSubtle,
                    shape = CircleShape,
                ),
        )
    }
}

/** The string for a suggested background, or its hex if the list ever gains one. */
@Composable
private fun matteNameRes(hex: String): Int = when (SUGGESTED_BACKGROUND_NAMES[hex.uppercase()]) {
    "white" -> R.string.reading_matte_white
    "cream" -> R.string.reading_matte_cream
    "sepia" -> R.string.reading_matte_sepia
    "sage" -> R.string.reading_matte_sage
    "sky" -> R.string.reading_matte_sky
    "charcoal" -> R.string.reading_matte_charcoal
    "navy" -> R.string.reading_matte_navy
    "trueBlack" -> R.string.reading_matte_trueblack
    // A colour added to the list without a name still announces something a reader can
    // act on, rather than nothing.
    else -> R.string.reading_matte_swatch
}

/** Black stands for "no colour", which is what a comic is read against. */
private fun matteSwatchColour(hex: String?): Color {
    val text = hex?.removePrefix("#") ?: return Color.Black
    val value = text.toLongOrNull(16) ?: return Color.Black
    return Color(
        red = ((value shr 16) and 0xFF) / 255f,
        green = ((value shr 8) and 0xFF) / 255f,
        blue = (value and 0xFF) / 255f,
    )
}

@Composable
private fun ScopeDefaults(
    scope: ThemeScope,
    memory: ShelfMemory,
    store: ReaderPreferences,
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
                        // The whole settings value, not just the preset: a preset carries
                        // its own typography, and a default that kept the previous one
                        // would not be the preset the reader chose.
                        store.save(
                            store.themes().settingDefault(
                                ShelfSettings(
                                    theme = app.storyarc.core.model.ReadingTheme(preset),
                                    values = preset.values,
                                ),
                                scope,
                            ),
                        )
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
private val ThemePreset.labelRes: Int
    get() = when (this) {
        ThemePreset.ORIGINAL -> R.string.preset_original
        ThemePreset.QUIET -> R.string.preset_quiet
        ThemePreset.PAPER -> R.string.preset_paper
        ThemePreset.BOLD -> R.string.preset_bold
        ThemePreset.CALM -> R.string.preset_calm
        ThemePreset.FOCUS -> R.string.preset_focus
    }
