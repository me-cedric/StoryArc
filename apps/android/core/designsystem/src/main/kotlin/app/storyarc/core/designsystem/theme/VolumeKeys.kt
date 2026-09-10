package app.storyarc.core.designsystem.theme

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Where a reader says "the volume buttons should turn my pages".
 *
 * `page-transitions` asks for the volume buttons as a turn trigger "where enabled in
 * settings", and a volume key never reaches Compose: it arrives at the `Activity`, and
 * only the activity can consume it before the system changes the volume. So the reader
 * cannot handle this itself — it can only offer a handler and let the host call it.
 *
 * A *mutable holder* provided downward rather than a value, because the direction is
 * backwards: a composition local flows down and this information flows up. The host
 * creates the holder and reads it from `onKeyDown`; the reader fills it in while it is on
 * screen and clears it on the way out.
 *
 * In the design system rather than a feature module so both readers and both hosts can
 * see it without a feature depending on a feature.
 */
class VolumeTurns {
    /**
     * Turns forward when `forward`, backward otherwise, and reports whether it did.
     *
     * `null` means no reader is on screen. The host also declines when the setting is off,
     * so a non-null handler is not on its own permission to use it.
     */
    var turn: ((forward: Boolean) -> Boolean)? = null
}

val LocalVolumeTurns = staticCompositionLocalOf { VolumeTurns() }

/**
 * Whether a tap in the leading or trailing third of a page turns it.
 *
 * `page-transitions` makes this a setting, and the setting lives on `AppSettings` at the
 * app layer while the gesture is answered inside the reader. A composition local rather
 * than a parameter threaded through five composables, for the reason [LocalVolumeTurns]
 * is one: the reader is a feature module and does not read the app's settings store.
 *
 * True by default, which is both the setting's default and the right answer for a
 * composition that has no shell above it -- a preview, or a test of the reader alone.
 */
val LocalTapTurnsPages = staticCompositionLocalOf { true }
