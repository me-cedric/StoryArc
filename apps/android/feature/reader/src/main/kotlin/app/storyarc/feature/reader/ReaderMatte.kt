package app.storyarc.feature.reader

import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingTheme

/**
 * Where [ReaderViewModel.chooseMatte] gets the pure rule.
 *
 * `ebook-reader`, *Fixed-layout EPUB*: "background colour ... remain[s] available, because
 * it applies to the container rather than the text" -- D34 is what notices the colour was
 * reachable only from Settings' own per-series default, never from the reader that is
 * actually open.
 *
 * A mirror of `app.storyarc.feature.settings`'s own `matting(hex, theme)`, not a shared
 * call: the two live in peer feature modules with no dependency between them, and the rule
 * is four lines -- `reading-themes` is the spec either one answers to, the same shape this
 * repository already accepts for `PageOrdering` and the rest of the format layer. iOS's
 * `ReaderMatte.matting(_:over:)` is the same mirror on that platform.
 *
 * `hex` cleared drops any custom colour and goes back to the theme's own. A theme stored as
 * Original, from before this scope had its own picker, refuses every palette, so the matte
 * goes over Paper instead -- Paper carries no axis a matte could clash with, which is all a
 * comic asks a preset for.
 */
internal fun matting(hex: String?, theme: ReadingTheme): ReadingTheme {
    if (hex == null) return theme.discardingCustomColours()
    val base = if (theme.preset.keepsPublisherStyles) ReadingTheme() else theme
    return base.adopting(ReaderPalette.derived(hex, hex))
}
