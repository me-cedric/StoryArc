public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// Drawn in place of the live transport once a book has run out.
///
/// `collections-and-reading-lists` task 7.2: "at the end of... an audiobook, offer
/// `library.next(after:)` the way the paged reader's end screen does". The comic reader's
/// own `EndOfPublication` lives in `StoryArcKit`'s `ReaderFeature`, which this module does
/// not depend on, so this is the same idea in the module that already owns the player's
/// chrome.
struct PlayerFinishedOffer: View {
    @Environment(\.theme) private var theme

    let next: Publication?
    let onOpenNext: (Publication) -> Void

    /// How many parts of the book that ended could not be played. Task 2.5, O12: a book whose
    /// last or only part fails ends the session, and this surface says how much was lost, in
    /// words and never in a dialog.
    var unreadableParts = 0

    var body: some View {
        VStack(spacing: StoryArcSpace.lg) {
            Text("player.finished", bundle: .module)
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)

            PlayerText.damage(unreadableParts: unreadableParts)
                .textRole(.caption)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)

            if let next {
                Button {
                    onOpenNext(next)
                } label: {
                    Text("player.finished.next \(next.displayTitle)", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
        .padding(.vertical, StoryArcSpace.xxl)
        .frame(maxWidth: .infinity)
    }
}
