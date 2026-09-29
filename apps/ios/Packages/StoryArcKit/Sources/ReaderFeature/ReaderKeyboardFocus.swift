internal import SwiftUI

/// Gives `.onKeyPress` a focused view to fire against.
///
/// `.focusable()` alone offers to become the first responder; nothing was asking it to,
/// so the arrow, page and space keys never fired on a device — a Mac's test host
/// focuses the one view in the window by default, which is why every other reader test
/// passed regardless. This claims it on appear, and again whenever the last sheet over
/// the reader closes: a sheet becomes the focused view while it is up, and dismissing
/// it does not hand focus back. Every sheet counts — the menu, the thumbnails, the
/// adjustments, the find and bookmarks sheet, and the note editor — because the one left
/// out is the one after which the keys stop working.
///
/// Split out of `ReaderView.swift`, which had reached the 400-line cap this project
/// enforces, the way `ReaderSystemChrome` already is for the same reason.
struct ReaderKeyboardFocus: ViewModifier {
    /// Whether any sheet is over the reader.
    let isCoveredBySheet: Bool

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: isCoveredBySheet) { _, isCovered in if !isCovered { isFocused = true } }
    }
}
