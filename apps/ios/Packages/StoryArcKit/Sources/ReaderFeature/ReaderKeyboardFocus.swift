internal import SwiftUI

/// Gives `.onKeyPress` a focused view to fire against.
///
/// `.focusable()` alone offers to become the first responder; nothing was asking it to,
/// so the arrow, page and space keys never fired on a device — a Mac's test host
/// focuses the one view in the window by default, which is why every other reader test
/// passed regardless. This claims it on appear, and again whenever a sheet that took
/// focus away closes: a sheet becomes the focused view while it is up, and dismissing
/// it does not hand focus back.
///
/// Split out of `ReaderView.swift`, which had reached the 400-line cap this project
/// enforces, the way `ReaderSystemChrome` already is for the same reason.
struct ReaderKeyboardFocus: ViewModifier {
    let isShowingMenu: Bool
    let isBrowsingThumbnails: Bool
    let isAdjusting: Bool

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: isShowingMenu) { _, isOpen in if !isOpen { isFocused = true } }
            .onChange(of: isBrowsingThumbnails) { _, isOpen in
                if !isOpen { isFocused = true }
            }
            .onChange(of: isAdjusting) { _, isOpen in if !isOpen { isFocused = true } }
    }
}
