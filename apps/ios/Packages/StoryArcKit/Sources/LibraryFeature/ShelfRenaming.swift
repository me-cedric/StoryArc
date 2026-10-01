internal import Foundation
internal import SwiftUI

public import StoryArcCore

/// The shelf a reader is renaming, and the name typed so far. Task 7.10.
struct ShelfRenameTarget: Identifiable {
    let isList: Bool
    let id: UUID
    var name: String

    init(_ collection: PublicationCollection) {
        isList = false
        id = collection.id
        name = collection.name
    }

    init(_ list: ReadingList) {
        isList = true
        id = list.id
        name = list.name
    }
}

extension LibraryModel {
    /// Dispatches to ``rename(collection:to:)`` or ``rename(list:to:)``, so `ShelvesView`'s
    /// own call is one line.
    func rename(_ target: ShelfRenameTarget) {
        if target.isList {
            rename(list: target.id, to: target.name)
        } else {
            rename(collection: target.id, to: target.name)
        }
    }
}

extension View {
    /// The alert `renameButton` opens — `ShelfCreation.swift`'s `.shelfCreation(_:name:...)`
    /// is the same idiom, a `TextField` inside an `alert(presenting:)`.
    func shelfRename(
        _ target: Binding<ShelfRenameTarget?>,
        onConfirm: @escaping (ShelfRenameTarget) -> Void
    ) -> some View {
        alert(
            Text("shelves.rename", bundle: .module),
            isPresented: Binding(
                get: { target.wrappedValue != nil },
                set: { if !$0 { target.wrappedValue = nil } }
            ),
            presenting: target.wrappedValue
        ) { asked in
            TextField(
                String(localized: "shelves.new.field", bundle: .module, locale: .storyArc),
                text: Binding(
                    get: { asked.name },
                    set: { target.wrappedValue?.name = $0 }
                )
            )
            Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            Button {
                onConfirm(asked)
                target.wrappedValue = nil
            } label: {
                Text("shelves.rename", bundle: .module)
            }
            .disabled(asked.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
