package app.storyarc.core.designsystem.theme

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingToolbarColors
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * The colours of the capsule that floats over a page, said once for both readers.
 *
 * **Why this left `:feature:reader` and became shared.** The comic reader named these and the
 * reflowable one did not, and the sweep of 2026-09-02 photographed the difference:
 * `android-comic-chrome.png` is a dark capsule with white glyphs over artwork, and
 * `android-epub-chrome.png` is `standardFloatingToolbarColors()` — Material's
 * `surfaceContainer`, a pale lavender lozenge laid straight over running body text with
 * sentences visible around its edges and nothing behind it. Same component, same position,
 * same two buttons; one of them had a scrim.
 *
 * `AGENTS.md`'s fifth non-negotiable is that chrome "recedes, auto-hides, never tints", and a
 * capsule the colour of the page recedes so far it stops being a control. So both readers now
 * take the treatment the comic reader had: the palette's own scrim, at the alpha the
 * hand-rolled pills used before the capsule replaced them, with white content.
 *
 * **White rather than a palette role, and a scrim rather than a surface.** What is behind
 * this capsule is not the app's surface — it is a comic page, which can be white, or a book
 * page, whose colour is the *reading theme's* and not the appearance's. Neither is a value
 * the scheme knows, so the only pair that holds over all of them is a dark wash and a white
 * glyph. That is a contrast decision rather than a brand one, which is why it does not go
 * through `MaterialTheme.colorScheme` and why turning Material You off does not change it.
 *
 * Pinned by `ReaderChromeColoursTest`, which asserts the pair against the real
 * `FloatingToolbarDefaults` rather than restating it.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun readerChromeColours(): FloatingToolbarColors =
    FloatingToolbarDefaults.standardFloatingToolbarColors(
        toolbarContainerColor = LocalStoryArcPalette.current.scrim.copy(alpha = SCRIM_ALPHA),
        toolbarContentColor = Color.White,
    )

/**
 * How much of the page shows through the capsule.
 *
 * Enough that the chrome is plainly a layer above the page rather than a hole in it, and
 * enough that a white glyph clears the 3:1 WCAG asks of a graphical object on the *whitest*
 * page either reader can draw — which is the worst case, and is close to the frame the sweep
 * complained about. Measured in `ReaderChromeColoursTest` rather than asserted here: over
 * pure white the pair reaches 3.79:1, so there is real headroom and not much of it, and a
 * lighter wash would spend it.
 */
private const val SCRIM_ALPHA = 0.6f
