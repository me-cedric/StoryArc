package app.storyarc.feature.epubreader

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import app.storyarc.core.designsystem.theme.StoryArcWindowClass
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues

/**
 * Whether the theme surface earns the anchored, non-modal presentation at this width.
 *
 * `native-experience`, *Theme sheet on a large screen*: the popover arrives "on a tablet",
 * which [StoryArcWindowClass.MEDIUM] is Material's own name for -- a portrait tablet or an
 * unfolded foldable, the first class with the room [ThemePopover] asks for. A plain function
 * beside [ThemeSurface] rather than the `>=` inlined at its one call site, because
 * `ThemeSurfaceTest` is what proves the boundary sits at medium and not at compact or
 * expanded, and a JVM test cannot reach a branch written only inside a composable.
 */
internal fun StoryArcWindowClass.showsAnchoredTheme(): Boolean = this >= StoryArcWindowClass.MEDIUM

/**
 * Level one of the theme surface, in whichever presentation the window's width earns it.
 *
 * `native-experience`, *Theme sheet on a large screen*: "it presents as a popover anchored
 * to its control rather than a full-width sheet, and the reader stays visible beside it".
 * D22 reads that for Android, where Material has no popover, as [ThemePopover] -- an
 * anchored, non-modal surface -- once [showsAnchoredTheme] says so. Narrower than that stays
 * [ThemeBottomSheet], which is what [EpubReaderActivity] drew on every width before this.
 *
 * [windowClass] defaults to the real one so every production call site reads unchanged;
 * [ThemeSurfaceTest] passes a chosen class directly; the branch does not care which gave it
 * one.
 *
 * Its own file, and the choice read here rather than inlined at the one call site: this is
 * the whole of what the width decides, and `EpubReaderActivity.kt` is already at the line
 * cap `scripts/line-cap.mjs` recorded for it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ThemeSurface(
    theme: ReadingTheme,
    values: ThemeValues,
    customPalette: ReaderPalette? = null,
    onAdopt: (ThemePreset) -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    onCustomise: () -> Unit,
    onDismiss: () -> Unit,
    chapter: String? = null,
    excerpt: String = "",
    windowClass: StoryArcWindowClass = rememberWindowClass(),
) {
    if (windowClass.showsAnchoredTheme()) {
        ThemePopover(
            theme = theme,
            values = values,
            customPalette = customPalette,
            onAdopt = onAdopt,
            onAdoptColours = onAdoptColours,
            onCustomise = onCustomise,
            onDismiss = onDismiss,
            chapter = chapter,
            excerpt = excerpt,
        )
    } else {
        ThemeBottomSheet(
            theme = theme,
            values = values,
            customPalette = customPalette,
            onAdopt = onAdopt,
            onAdoptColours = onAdoptColours,
            onCustomise = onCustomise,
            onDismiss = onDismiss,
            chapter = chapter,
            excerpt = excerpt,
        )
    }
}
