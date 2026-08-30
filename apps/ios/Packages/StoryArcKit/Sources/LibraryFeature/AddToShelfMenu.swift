public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// Where a publication can be put.
///
/// `collections-and-reading-lists`: "a publication may belong to any number of collections".
/// So this offers every one of them rather than a picker that implies a single answer, and
/// shows nothing at all when there is nowhere to put it.
struct AddToShelfMenu: View {
    let model: LibraryModel
    let publication: Publication
    /// Called with the server's name when a list cannot hold this publication. The alert
    /// lives in the parent: a context menu cannot present one.
    let onRefused: (String) -> Void

    var body: some View {
        let shelves = model.shelves
        let already = Set(shelves.collections(containing: publication.id).map(\.id))
        let isRead = model.finishedPublications.contains(publication.id)

        // `reading-progress`: a reader can mark a publication read "manually", which until
        // now they could only do by turning every page of it.
        Button {
            Task { await model.mark(publication, read: !isRead) }
        } label: {
            Label(
                isRead
                    ? String(localized: "library.mark.unread", bundle: .module, locale: .storyArc)
                    : String(localized: "library.mark.read", bundle: .module, locale: .storyArc),
                systemImage: isRead ? "circle" : "checkmark.circle"
            )
        }

        // A server's own lists, offered like any other. Whether this publication can go in
        // one is the server's rule, not something to hide by leaving the row out: a list a
        // reader cannot see is a list they will look for.
        ForEach(model.serverLists) { list in
            Button {
                Task {
                    if await model.add(publication, toServerList: list) == false {
                        onRefused(list.server.title)
                    }
                }
            } label: {
                Text("shelves.addTo \(list.title) \(list.server.title)", bundle: .module)
            }
        }

        if !shelves.collections.isEmpty || !shelves.lists.isEmpty {
            Menu {
                ForEach(shelves.collections) { collection in
                    Button {
                        model.add([publication.id], toCollection: collection.id)
                    } label: {
                        if already.contains(collection.id) {
                            Label(collection.name, systemImage: "checkmark")
                        } else {
                            Text(collection.name)
                        }
                    }
                    // Already in it, so there is nothing this tap would change.
                    .disabled(already.contains(collection.id))
                }

                if !shelves.lists.isEmpty {
                    Divider()
                    ForEach(shelves.lists) { list in
                        Button {
                            model.append([publication.id], toList: list.id)
                        } label: {
                            Text(list.name)
                        }
                        .disabled(list.entries.contains(publication.id))
                    }
                }
            } label: {
                Label {
                    Text("shelves.addTo", bundle: .module)
                } icon: {
                    Image(systemName: "text.badge.plus")
                }
            }
        }
    }
}

extension View {
    /// The alert a server's refusal raises, and the local list it offers instead.
    ///
    /// A modifier rather than a copy per cell: the grid, the continue row and the list
    /// all present `AddToShelfMenu`, a context menu cannot raise an alert of its own,
    /// and three copies of the same alert is how two of them end up saying different
    /// things.
    func refusedByServer(
        _ server: Binding<String?>,
        model: LibraryModel,
        publication: Publication
    ) -> some View {
        alert(
            Text("shelves.serverOnly.title", bundle: .module),
            isPresented: Binding(
                get: { server.wrappedValue != nil },
                set: { if !$0 { server.wrappedValue = nil } }
            )
        ) {
            Button {
                // The offer the spec asks for: a local list can hold anything.
                model.create(list: publication.displayTitle)
                if let made = model.shelves.lists.last {
                    model.append([publication.id], toList: made.id)
                }
                server.wrappedValue = nil
            } label: {
                Text("shelves.serverOnly.local", bundle: .module)
            }
            Button(role: .cancel) { server.wrappedValue = nil } label: {
                Text("shelves.cancel", bundle: .module)
            }
        } message: {
            Text("shelves.serverOnly.body \(server.wrappedValue ?? "")", bundle: .module)
        }
    }
}
