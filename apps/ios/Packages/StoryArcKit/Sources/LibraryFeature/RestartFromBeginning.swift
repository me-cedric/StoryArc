internal import SwiftUI

public import StoryArcCore

/// Whether *Start from the beginning* belongs in a menu, and the confirmation it owes.
///
/// `reading-progress`: the action is "available from the publication's own cover in the
/// library" and "clears progress only after confirmation".
///
/// **Written down because the menu drew a button nothing was wired to.** `CoverList`
/// opened ``AddToShelfMenu`` with a trailing closure, which under Swift's forward-scan
/// rule binds to `onRefused` — the first argument with no default — leaving `onRestart` on
/// the empty closure it defaulted to. The menu offered the action anyway, so a reader in
/// the list layout long-pressed a cover, tapped *Start from the beginning*, and nothing
/// happened at all: no confirmation, no clear, no message. Nothing failed, which is why no
/// test caught it; a test asserting the button exists would have passed too.
///
/// So the rule now includes *whether anyone is listening*, and a menu with no handler
/// draws no button. Android's `AddToShelfSheet` already gated its row on `onRestart !=
/// null` and was immune by construction; ``RestartOffer`` is that guard written as
/// something both platforms can assert.
public enum RestartOffer {
    /// Whether to draw the action.
    ///
    /// Three conditions, all of them refusals:
    ///
    /// - **One publication.** A set of them has no single beginning to go back to.
    /// - **Something to clear.** On an unread publication the action would start it from
    ///   the beginning it is already at.
    /// - **Somewhere to send it.** The confirmation `reading-progress` requires cannot be
    ///   presented from inside a context menu, so the action is always the parent's to
    ///   perform. A menu whose parent did not take it has nothing to offer.
    public static func isOffered(
        publicationCount: Int,
        hasSomethingToClear: Bool,
        isWired: Bool
    ) -> Bool {
        publicationCount == 1 && hasSomethingToClear && isWired
    }
}

extension View {
    /// The confirmation `reading-progress` requires before progress is cleared.
    ///
    /// A modifier rather than a block copied into each surface that offers the action. The
    /// grid had it and the list did not, and two shelves that clear progress differently is
    /// the same defect one step later — the dialog, its destructive role and its wording
    /// now come with the action wherever it is offered.
    ///
    /// Destructive because it is: the position is the only copy the app promises never to
    /// lose.
    func restartConfirmation(
        _ publication: Binding<Publication?>,
        model: LibraryModel
    ) -> some View {
        confirmationDialog(
            Text(
                "library.restart.title \(publication.wrappedValue?.displayTitle ?? "")",
                bundle: .module
            ),
            isPresented: Binding(
                get: { publication.wrappedValue != nil },
                set: { if !$0 { publication.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let target = publication.wrappedValue {
                    Task { await model.restart(target) }
                }
                publication.wrappedValue = nil
            } label: {
                Text("library.restart.confirm", bundle: .module)
            }
        } message: {
            Text("library.restart.body", bundle: .module)
        }
    }
}
