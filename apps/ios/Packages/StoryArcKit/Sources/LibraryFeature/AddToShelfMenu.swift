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
                    ? String(localized: "library.mark.unread", bundle: .module)
                    : String(localized: "library.mark.read", bundle: .module),
                systemImage: isRead ? "circle" : "checkmark.circle"
            )
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
