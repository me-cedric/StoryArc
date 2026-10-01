internal import SwiftUI

public import StoryArcCore

/// The colour behind the page, chosen live and kept for the series.
///
/// `ebook-reader`, *Fixed-layout EPUB*: "background colour, brightness and page transition
/// remain available, because they apply to the container rather than the text" — the comic
/// reader opens the same pages, and D34 is what notices the colour was reachable only from
/// Settings' own per-series default, never from the reader that is actually open.
///
/// `reading-themes`: a custom background "applies to the area around the page and not to
/// the page itself, because tinting artwork is not a reading preference" — which is why this
/// sets ``ReaderModel/matte`` and never the image-adjustment filters `AdjustmentsSheet`
/// already offers. Those darken or invert the artwork; this never touches a pixel of it.
public extension ReaderModel {
    /// Chooses the matte, or no matte, for this shelf from now on.
    ///
    /// Goes through ``ReaderModel/remember(_:)``, the one path that writes
    /// `ReaderPreferences.remembering(_:for:.fixedLayout)` — the same store
    /// `ReadingDefaults.matting(_:over:)` writes the global default to, so a reader who sets
    /// one here and later changes their mind in Settings is moving the same value either way.
    func chooseMatte(_ hex: String?) {
        var updated = settings
        updated.theme = ReaderMatte.matting(hex, over: updated.theme)
        remember(updated)
    }
}

/// Where ``ReaderModel/chooseMatte(_:)`` gets the pure rule.
///
/// A mirror of `ReadingDefaults.matting(_:over:)` in `SettingsFeature`, not a shared call:
/// the two live in peer feature modules with no dependency between them, and the rule is
/// four lines — `reading-themes` is the spec either one answers to, so the duplication is of
/// a translation of the spec into code, the same shape this repository already accepts for
/// `PageOrdering` and the rest of the format layer.
enum ReaderMatte {
    /// `hex` cleared drops any custom colour and goes back to the theme's own. A theme
    /// stored as Original, from before this scope had its own picker, refuses every
    /// palette, so the matte goes over Paper instead — Paper carries no axis a matte could
    /// clash with, which is all a comic asks a preset for.
    static func matting(_ hex: String?, over theme: ReadingTheme) -> ReadingTheme {
        guard let hex else { return theme.discardingCustomColours() }
        let base = theme.preset.keepsPublisherStyles ? ReadingTheme(preset: .paper) : theme
        return base.adopting(ReaderPalette.derived(name: hex, background: hex))
    }
}

extension ReaderView {
    /// The destination the menu's "themes" row opens for a comic or a scan.
    ///
    /// Here rather than inline in `ReaderView.swift`, which is at its line cap: the call
    /// needs nothing from that file beyond the three properties it already exposed for it
    /// (`adjustments`, `shelf`, `cropsThisPage`), plus the model this file's own matte lives
    /// beside.
    var adjustmentsSheet: some View {
        AdjustmentsSheet(adjustments: $adjustments, shelf: shelf, cropsThisPage: cropsThisPage, model: model)
    }
}
