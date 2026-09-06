internal import SwiftUI

internal import Kavita

/// A shelf the reader is making, and the places it could be kept.
///
/// `collections-and-reading-lists`: a new shelf "is stored locally by default, or on a server
/// if the user chooses one that supports collections", and "the storage location is stated at
/// creation, not discovered later". Both halves need the choice to exist before the shelf
/// does, which is what this holds — the kind, the name, and the servers that could take it.
///
/// Only a server that has just answered when asked for shelves of this kind is offered. That
/// is the same rule the copy-onto-a-server offer already follows: reachable and able to hold
/// one, which an empty answer cannot tell apart from no answer.
///
/// Android's `ShelfCreation` offers the same destinations in the same order.
struct ShelfDraft: Identifiable {
    /// Which of the two shelves is being made. The reader is taught the difference once, and
    /// the sentence they read has to keep it.
    enum Kind: String, Identifiable {
        case collection
        case list

        var id: String { rawValue }
    }

    let id = UUID()
    let kind: Kind
    /// The servers that could hold a shelf of this kind, in the order they were found.
    let servers: [KavitaPage]
}

/// Making a shelf somewhere other than this device.
enum ShelfCreation {

    /// Makes the shelf on the server, and answers with it.
    ///
    /// Nil when the server refused. The caller says so rather than pretending: a shelf the
    /// reader was told is kept on a server, and is not, is worse than an error they can act
    /// on. Nothing is written locally either — the alternative would be a shelf whose stated
    /// home is a lie.
    static func make(
        _ kind: ShelfDraft.Kind,
        named title: String,
        on page: KavitaPage
    ) async -> ServerShelf? {
        let client = KavitaClient(address: page.address)
        switch kind {
        case .collection:
            guard let made = try? await client.createCollection(named: title) else { return nil }
            return ServerShelf(server: page, id: made.id, title: made.title, isList: false)
        case .list:
            guard let made = try? await client.createList(named: title) else { return nil }
            return ServerShelf(server: page, id: made.id, title: made.title, isList: true)
        }
    }
}

extension View {
    /// The question a shelf is made through.
    ///
    /// One button per destination rather than a picker, because the destinations are a short
    /// list and a button already says what it will do. The device comes first and is the
    /// default the spec names; a server follows only when it has just answered.
    ///
    /// The message states where the shelf will be kept before it exists, which is the
    /// scenario's second half — "not discovered later".
    func shelfCreation(
        _ draft: Binding<ShelfDraft?>,
        name: Binding<String>,
        onDevice: @escaping (ShelfDraft.Kind, String) -> Void,
        onServer: @escaping (ShelfDraft.Kind, String, KavitaPage) -> Void
    ) -> some View {
        alert(
            Text(
                draft.wrappedValue?.kind == .list ? "shelves.new.list" : "shelves.new.collection",
                bundle: .module
            ),
            isPresented: Binding(
                get: { draft.wrappedValue != nil },
                set: { if !$0 { draft.wrappedValue = nil } }
            ),
            presenting: draft.wrappedValue
        ) { asked in
            TextField(
                String(localized: "shelves.new.field", bundle: .module, locale: .storyArc),
                text: name
            )
            Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            Button {
                onDevice(asked.kind, name.wrappedValue)
            } label: {
                Text(asked.servers.isEmpty ? "shelves.create" : "shelves.new.here", bundle: .module)
            }
            ForEach(asked.servers) { page in
                Button {
                    onServer(asked.kind, name.wrappedValue, page)
                } label: {
                    Text(page.title)
                }
            }
        } message: { asked in
            // One location means saying which it is; more than one means saying that the
            // choice is being made now. Either way the reader is told before, not after.
            Text(
                asked.servers.isEmpty ? "shelves.new.storedLocally" : "shelves.new.chooseWhere",
                bundle: .module
            )
        }
    }
}
