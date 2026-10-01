internal import SwiftUI

internal import Kavita
internal import Persistence

/// The server shelf a reader has asked to delete and not yet answered for.
///
/// `collections-and-reading-lists`: a server shelf is "the same kind of object as locally
/// created ones", and `ShelfDeletion` is that promise for a local one — this is its twin for
/// one the server holds. Deleting is confirmed the same way, with the same two sentences
/// local shelves use: the publications themselves are never at risk, on a server any more
/// than on this device.
struct ServerShelfDeletion: Identifiable, Equatable {
    let id: Int
    let name: String
    let isCollection: Bool
    let sourceId: String
    let address: KavitaAddress

    init(_ shelf: ServerShelf) {
        id = shelf.id
        name = shelf.title
        isCollection = !shelf.isList
        sourceId = shelf.server.id
        address = shelf.server.address
    }

    var message: Text {
        isCollection
            ? Text("shelves.delete.collection.body", bundle: .module)
            : Text("shelves.delete.list.body", bundle: .module)
    }
}

/// One server shelf's cell in `ShelvesView`'s grid: the cover, the route to its own screen,
/// and the one action a server row offers. A free function rather than a `ShelvesView`
/// method, so the two call sites — a collection's grid and a list's — shrink to this one
/// line each, which is what let the delete action join them without crossing the 400-line
/// cap `ShelvesView.swift` is already at.
@ViewBuilder
func serverShelfCell<Destination: View>(
    _ shelf: ServerShelf,
    pending: Int = 0,
    model: LibraryModel,
    deleting: Binding<ServerShelfDeletion?>,
    @ViewBuilder destination: () -> Destination
) -> some View {
    NavigationLink {
        destination()
    } label: {
        ServerShelfCardView(shelf: shelf, pending: pending, model: model)
    }
    .buttonStyle(.plain)
    .contextMenu {
        Button(role: .destructive) {
            deleting.wrappedValue = ServerShelfDeletion(shelf)
        } label: {
            Label {
                Text("shelves.delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }
}

extension View {
    /// The confirmation `ShelvesView` raises for a server shelf, and the queued delete it
    /// sends once a reader confirms. `shelves` is its own `serverShelves`, spliced in place
    /// rather than through a closure, for the one line this buys `ShelvesView.body`.
    func serverShelfDeletionConfirmation(
        _ deleting: Binding<ServerShelfDeletion?>,
        removingFrom shelves: Binding<[ServerShelf]>
    ) -> some View {
        serverShelfDeletionConfirmation(deleting) { deletion in
            shelves.wrappedValue.removeAll {
                $0.server.id == deletion.sourceId && $0.id == deletion.id && $0.isList != deletion.isCollection
            }
        }
    }

    private func serverShelfDeletionConfirmation(
        _ deleting: Binding<ServerShelfDeletion?>,
        onDeleted: @escaping (ServerShelfDeletion) -> Void
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
                onDeleted(deletion)
                Task {
                    await KavitaSync.deleteShelf(
                        deletion.id,
                        isCollection: deletion.isCollection,
                        on: deletion.sourceId,
                        to: deletion.address,
                        in: KavitaProgressStore()
                    )
                }
                deleting.wrappedValue = nil
            } label: {
                Text("shelves.delete", bundle: .module)
            }
        } message: { deletion in
            deletion.message
        }
    }
}
