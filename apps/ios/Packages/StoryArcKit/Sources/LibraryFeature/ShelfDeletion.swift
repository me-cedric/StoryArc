internal import SwiftUI

internal import StoryArcCore

/// A shelf the reader has asked to delete, and has not answered for yet.
///
/// `collections-and-reading-lists`: when a reader deletes a collection "the app confirms and
/// states plainly that the publications themselves are not deleted". A confirmation needs
/// something to hold between the question and the answer, and this is it — the name, so the
/// question can say which shelf, and the kind, so the sentence can name what actually goes.
///
/// Confirmation rather than the ten-second undo the bulk actions use. The spec names the
/// two halves of this scenario and both are the dialogue's: a reader deleting a shelf is
/// afraid of losing the books on it, and a bar that appears *after* the shelf has gone
/// answers that fear too late to be reassurance. The undo is right for an action whose
/// result is visible and reversible; this one's result is an absence.
///
/// The value is the whole safety property. While one of these exists nothing has been
/// written, and ``apply(to:)`` — the only thing that writes — is reached from the confirming
/// button alone.
///
/// Android's `ShelfDeletion` is the same type, asserted case for case.
struct ShelfDeletion: Identifiable, Equatable {
    /// Which of the two shelves this is.
    ///
    /// Not a flag on one type for the reason the spec gives for keeping a collection and a
    /// reading list apart, and because the sentence the reader reads differs by exactly this
    /// word: what is going is *the collection* or *the reading list*, never "the shelf".
    enum Kind: Equatable {
        case collection
        case list
    }

    let id: UUID
    let name: String
    let kind: Kind

    init(_ collection: PublicationCollection) {
        id = collection.id
        name = collection.name
        kind = .collection
    }

    init(_ list: ReadingList) {
        id = list.id
        name = list.name
        kind = .list
    }

    /// Carries the deletion out. Nothing that happened before this call changed anything.
    ///
    /// It takes ``Shelves`` and answers ``Shelves``, and a publication is neither. That is
    /// the sentence the dialogue makes to the reader, held up by the types: a shelf is a set
    /// of identities, and deleting one can only ever drop the set.
    func apply(to shelves: Shelves) -> Shelves {
        switch kind {
        case .collection: shelves.deleting(collection: id)
        case .list: shelves.deleting(list: id)
        }
    }
}

extension View {
    /// The question a shelf is deleted through.
    ///
    /// Both halves the spec asks for, and the second is the one that earns its place: what a
    /// reader fears when they delete a shelf is losing the books on it, so the message says
    /// they keep them and says nothing else.
    func shelfDeletionConfirmation(
        _ deleting: Binding<ShelfDeletion?>,
        model: LibraryModel
    ) -> some View {
        confirmationDialog(
            Text("shelves.delete.title \(deleting.wrappedValue?.name ?? "")", bundle: .module),
            isPresented: Binding(
                get: { deleting.wrappedValue != nil },
                set: { if !$0 { deleting.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleting.wrappedValue
        ) { deletion in
            Button(role: .destructive) {
                model.delete(deletion)
                deleting.wrappedValue = nil
            } label: {
                Text("shelves.delete", bundle: .module)
            }
        } message: { deletion in
            Text(
                deletion.kind == .list
                    ? "shelves.delete.list.body"
                    : "shelves.delete.collection.body",
                bundle: .module
            )
        }
    }
}
