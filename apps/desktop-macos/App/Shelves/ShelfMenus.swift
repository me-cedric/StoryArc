import StoryArcCore
import SwiftUI

/// A name the reader is asked for: a new shelf (with what goes on it), or a new name for one.
struct ShelfNaming: Identifiable, Equatable {
    enum Purpose: Equatable {
        case create(ShelfRow.Kind, adding: [String])
        case rename(ShelfPin)
    }

    let id = UUID()
    let purpose: Purpose
    var name: String
}

/// The questions a shelf asks: its name, and whether to delete it. Held apart from any one
/// window so the sidebar, a cover's menu and a shelf page ask through the same alert.
@MainActor
@Observable
final class ShelfPrompts {
    static let shared = ShelfPrompts()
    var naming: ShelfNaming?
    var deleting: ShelfRow?
    var downloading: BulkDownloadOffer?
    var undo: BulkMarkUndo?
}

/// *Add to Shelf*, in a cover's context menu: each shelf, then a new collection or list.
///
/// `docs/designs/desktop/macos.md` section 7. With several covers selected it adds them all.
struct AddToShelfMenu: View {
    let library: MacLibrary
    let ids: [String]

    var body: some View {
        Menu {
            ForEach(library.shelfRows) { row in
                Button { library.add(ids, to: row.pin) } label: { Label(row.name, systemImage: row.symbolName) }
            }
            if !library.shelfRows.isEmpty { Divider() }
            Button {
                ShelfPrompts.shared.naming = ShelfNaming(purpose: .create(.collection, adding: ids), name: "")
            } label: { Text("desktop.shelves.newCollection") }
            Button {
                ShelfPrompts.shared.naming = ShelfNaming(purpose: .create(.list, adding: ids), name: "")
            } label: { Text("desktop.shelves.newList") }
        } label: {
            Text("desktop.shelves.addTo")
        }
    }
}

/// A shelf's own menu: in the sidebar, and at the head of its page.
struct ShelfRowMenu: View {
    let library: MacLibrary
    let row: ShelfRow

    /// Everything on the shelf that is still in the library, for the whole-shelf actions.
    private var members: Set<String> {
        let shelves = library.model.shelves
        return Set(MacShelves.members(of: row.pin, in: shelves, library: library.model.publications).map(\.id))
    }

    var body: some View {
        if !row.isEmpty {
            Button { Task { await library.markOffering(members, read: true) } } label: {
                Text("desktop.bulk.markAllRead")
            }
            Button { Task { await library.markOffering(members, read: false) } } label: {
                Text("desktop.bulk.markAllUnread")
            }
            if !library.downloadable(among: members).isEmpty {
                Button { library.offerDownload(members) } label: { Text("desktop.bulk.downloadAll") }
            }
            Divider()
        }
        Button { ShelfPrompts.shared.naming = ShelfNaming(purpose: .rename(row.pin), name: row.name) } label: {
            Text("desktop.shelves.rename")
        }
        Button { ShelfPins.shared.toggle(row.pin) } label: {
            Text(row.isPinned ? "desktop.shelves.unpin" : "desktop.shelves.pin")
        }
        Divider()
        Button(role: .destructive) { ShelfPrompts.shared.deleting = row } label: { Text("desktop.shelves.delete") }
    }
}

extension View {
    /// The name prompt and the delete confirmation every shelf action goes through.
    func shelfPrompts(_ library: MacLibrary, onCreated: @escaping (ShelfPin) -> Void = { _ in }) -> some View {
        modifier(ShelfPromptsModifier(library: library, onCreated: onCreated))
    }
}

private struct ShelfPromptsModifier: ViewModifier {
    let library: MacLibrary
    let onCreated: (ShelfPin) -> Void

    func body(content: Content) -> some View {
        let prompts = ShelfPrompts.shared
        content
            .alert(
                title,
                isPresented: Binding(get: { prompts.naming != nil }, set: { if !$0 { prompts.naming = nil } })
            ) {
                TextField(text: Binding(
                    get: { prompts.naming?.name ?? "" }, set: { prompts.naming?.name = $0 }
                )) { Text("desktop.shelves.name") }
                Button { commit() } label: { Text("desktop.shelves.save") }
                Button(role: .cancel) { prompts.naming = nil } label: { Text("desktop.sheet.cancel") }
            }
            .confirmationDialog(
                Text("desktop.shelves.delete.title \(prompts.deleting?.name ?? "")"),
                isPresented: Binding(get: { prompts.deleting != nil }, set: { if !$0 { prompts.deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    if let row = prompts.deleting { Task { await library.deleteShelf(row.pin) } }
                    prompts.deleting = nil
                } label: { Text("desktop.shelves.delete.confirm") }
            } message: {
                Text("desktop.shelves.delete.body")
            }
    }

    private var title: Text {
        switch ShelfPrompts.shared.naming?.purpose {
        case .create(.collection, _): Text("desktop.shelves.newCollection.title")
        case .create(.list, _): Text("desktop.shelves.newList.title")
        case .rename, nil: Text("desktop.shelves.rename.title")
        }
    }

    private func commit() {
        guard let naming = ShelfPrompts.shared.naming else { return }
        ShelfPrompts.shared.naming = nil
        switch naming.purpose {
        case let .create(kind, ids):
            if let pin = library.createShelf(kind, named: naming.name, with: ids) { onCreated(pin) }
        case let .rename(pin):
            library.rename(pin, to: naming.name)
        }
    }
}
