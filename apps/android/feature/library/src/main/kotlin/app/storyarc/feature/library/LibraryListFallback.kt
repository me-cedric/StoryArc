package app.storyarc.feature.library

import app.storyarc.core.designsystem.grid.isAccessibilityFontScale
import app.storyarc.core.model.LibraryLayout

/**
 * Whether the shelf draws [CoverList] regardless of the reader's own stored [layout].
 *
 * `library-browsing` asks for a grid and a compact list "for a library too large to
 * recognise by artwork alone" — and a library is also too large to recognise by artwork
 * once an accessibility font scale has widened every caption onto several lines of its own
 * cover's width, which a reader reaches independently of which layout they stored. Pure, so
 * `LibraryListFallbackTest` can assert it without composing a shelf; iOS's
 * `libraryFallsBackToList(stored:textSize:)` is the same rule.
 *
 * **The stored preference is never touched.** This answers "what to draw", not "what to
 * remember" — a reader who shrinks their text back finds the grid exactly where they left
 * it, because [layout] was read, not overwritten.
 *
 * Its own file rather than a few lines in `LibraryScreen.kt`: that file sat one line under
 * the 800-line cap, and a rule worth testing on its own is also worth finding on its own.
 */
internal fun libraryFallsBackToList(layout: LibraryLayout, fontScale: Float): Boolean =
    layout == LibraryLayout.LIST || isAccessibilityFontScale(fontScale)
