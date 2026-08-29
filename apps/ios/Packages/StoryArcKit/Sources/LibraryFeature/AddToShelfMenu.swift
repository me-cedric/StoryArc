internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Where a publication can be put.
///
/// `collections-and-reading-lists`: "a publication may belong to any number of collections".
/// So this offers every one of them rather than a picker that implies a single answer, and
/// shows nothing at all when there is nowhere to put it.
///
/// Takes a set rather than one publication, because the spec also asks for publications to
/// be "selected in bulk from the library" and a bulk add is this menu with more than one
/// thing in it. A context menu passes the one cover it was opened on; the selection bar
/// passes what the reader picked. There is no second implementation of either.
struct AddToShelfMenu: View {
    let model: LibraryModel
    let publications: [Publication]
    /// Called with the server's name when a list cannot hold what was offered. The alert
    /// lives in the parent: a context menu cannot present one.
    let onRefused: (String) -> Void
    /// What the action changed, for a caller that offers an undo. Nil for one publication
    /// out of a context menu, which has nothing to undo it with.
    var onChange: ((BulkUndo) -> Void)?

    private var ids: Set<String> { Set(publications.map(\.id)) }

    /// What the mark button would do.
    ///
    /// Read, unless every one of them already is — which for a single cover is the same
    /// read/unread toggle it has always been.
    private var marksRead: Bool { !ids.isSubset(of: model.finishedPublications) }

    /// Asks the parent to confirm starting over. Same reason as `onRefused`: the
    /// confirmation `reading-progress` requires cannot be presented from inside a menu.
    var onRestart: () -> Void = {}

    var body: some View {
        let shelves = model.shelves

        // `reading-progress`: a reader can mark a publication read "manually", which until
        // now they could only do by turning every page of it.
        Button {
            Task {
                let changed = await model.mark(selection: ids, read: marksRead)
                report(.read(marksRead), changed)
            }
        } label: {
            Label(
                marksRead
                    ? String(localized: "library.mark.read", bundle: .module, locale: .storyArc)
                    : String(localized: "library.mark.unread", bundle: .module, locale: .storyArc),
                systemImage: marksRead ? "checkmark.circle" : "circle"
            )
        }

        // `reading-progress`: "a 'Start from the beginning' action is available ... and it
        // clears progress only after confirmation". Offered only where there is something
        // to clear — on an unread publication it would start it from the beginning it is
        // already at — and only on one publication, because a set of them has no single
        // beginning to go back to.
        if let publication = publications.count == 1 ? publications.first : nil,
           model.finishedPublications.contains(publication.id)
            || model.readFraction(of: publication) != nil {
            Button {
                onRestart()
            } label: {
                Label(
                    String(localized: "library.restart", bundle: .module, locale: .storyArc),
                    systemImage: "arrow.counterclockwise"
                )
            }
        }

        // A server's own lists, offered like any other. Whether these publications can go in
        // one is the server's rule, not something to hide by leaving the row out: a list a
        // reader cannot see is a list they will look for.
        ForEach(model.serverLists) { list in
            Button {
                Task { await offer(list) }
            } label: {
                Text("shelves.addTo \(list.title) \(list.server.title)", bundle: .module)
            }
        }

        if !shelves.collections.isEmpty || !shelves.lists.isEmpty {
            Menu {
                collectionButtons(shelves)
                if !shelves.lists.isEmpty {
                    Divider()
                    listButtons(shelves)
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

    @ViewBuilder
    private func collectionButtons(_ shelves: Shelves) -> some View {
        ForEach(shelves.collections) { collection in
            let joining = BulkSelection.joining(ids, of: collection)
            Button {
                report(.collection(collection.id), model.add(selection: ids, toCollection: collection.id))
            } label: {
                if joining.isEmpty {
                    Label(collection.name, systemImage: "checkmark")
                } else {
                    Text(collection.name)
                }
            }
            // Every one of them is already in it, so there is nothing this tap would change.
            .disabled(joining.isEmpty)
        }
    }

    @ViewBuilder
    private func listButtons(_ shelves: Shelves) -> some View {
        ForEach(shelves.lists) { list in
            let appending = BulkSelection.appending(ids, to: list, inOrderOf: model.visible.map(\.id))
            Button {
                report(.list(list.id), Set(model.append(selection: ids, toList: list.id)))
            } label: {
                Text(list.name)
            }
            .disabled(appending.isEmpty)
        }
    }

    /// Offers the whole set to a server's list, one publication at a time.
    ///
    /// Refused once rather than once per publication: a selection of forty from a folder
    /// would otherwise raise forty identical alerts about the same server.
    private func offer(_ list: ServerShelf) async {
        var accepted = 0
        for publication in publications {
            accepted += await model.add(publication, toServerList: list) ? 1 : 0
        }
        if accepted < publications.count { onRefused(list.server.title) }
    }

    private func report(_ kind: BulkUndo.Kind, _ changed: Set<String>) {
        guard !changed.isEmpty else { return }
        onChange?(BulkUndo(kind: kind, ids: changed))
    }
}
