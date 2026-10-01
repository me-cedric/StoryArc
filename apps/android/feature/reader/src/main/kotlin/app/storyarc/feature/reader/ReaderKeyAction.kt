package app.storyarc.feature.reader

import androidx.compose.ui.input.key.Key

/**
 * Which action, if any, a key press means for the comic reader.
 *
 * Pulled out of [ReaderScreen]'s `onKeyEvent` so the mapping is testable with no Compose
 * tree at all -- the same reason `handleTap`'s zone math already has `ReaderTapZonesTest`.
 * `page-transitions`: arrow, page and space keys turn the page, and Enter toggles the
 * chrome the same way a centre tap does -- no key did that before this.
 */
internal enum class ReaderKeyAction {
    TurnBackward, TurnForward, PreviousInOrder, NextInOrder, ToggleChrome,
    ;

    companion object {
        fun of(key: Key): ReaderKeyAction? = when (key) {
            Key.DirectionLeft -> TurnBackward
            Key.DirectionRight -> TurnForward
            Key.PageUp -> PreviousInOrder
            Key.PageDown, Key.Spacebar -> NextInOrder
            Key.Enter, Key.NumPadEnter -> ToggleChrome
            else -> null
        }
    }
}
