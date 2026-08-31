internal import SwiftUI

internal import DesignSystem

/// The way back from a jump.
///
/// `ebook-reader`: "a longer jump navigates with a control to return to where they were",
/// and the scenario after it says the same control answers every long jump — a link, a
/// contents entry, a bookmark, a search hit — "because these are one act from the reader's
/// side". So this is one control with one label, not four.
///
/// A word rather than a glyph. The four buttons at the top of the chrome say what they do
/// by being a cross, a bookmark, a list; there is no symbol that reads as *where you were
/// a moment ago*, and a back arrow beside a page-turn gesture would be read as a page.
///
/// It appears where the read-aloud transport does, above the percentage rather than among
/// the buttons at the top: it comes and goes, and a control that appeared up there would
/// move the four that are always present.
///
/// Android's `EpubChrome` draws the same decision in Compose, from the same string.
struct ReturnControl: View {
    @Environment(\.theme) private var theme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("return.title", bundle: .module)
        }
        // Prominent, not plain. This is an offer to act — the shape the system gives a
        // *Done* — and `.glassProminent` is the variant meant to carry a tint. On plain
        // glass the same tint would flatten the material into an opaque pill, which is
        // the defect `ReaderChrome` explains.
        .buttonStyle(.glassProminent)
        .tint(theme.accent)
    }
}
