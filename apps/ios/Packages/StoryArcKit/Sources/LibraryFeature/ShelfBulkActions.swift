internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Acting on a whole collection or reading list at once.
///
/// `collections-and-reading-lists`' last requirement: a reader downloads "an entire
/// collection or reading list" and is told "the item count and total size before starting",
/// or marks one read, "and the action is undoable for 10 seconds".
///
/// A modifier rather than two copies of a toolbar, because a collection and a list differ in
/// how they are *shown* — a grid and a numbered run — and not at all in what can be done to
/// everything inside them. The actions are the same ones the library's selection bar uses,
/// handed the membership instead of a selection.
struct ShelfBulkActions: ViewModifier {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    /// Everything the shelf holds. An entry whose publication has gone is simply not in it.
    let members: Set<String>

    /// The list this shelf is, when it is a local reading list that could go on a server.
    /// Nil for a collection, and for a list a server already holds.
    var promoting: ReadingList?

    @State private var undo: BulkUndo?
    @State private var isAllOnDevice = false
    @State private var isPromoting = false

    /// What the download would copy and what it weighs, once the reader has asked.
    ///
    /// Worked out on the tap rather than on every redraw: both halves read the download
    /// store off disk, and a computed property would do that on each pass over the screen.
    @State private var pending: (ids: Set<String>, bytes: Int64)?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let undo {
                    BulkUndoBar(record: undo, model: model) { self.undo = nil }
                        .storyArcGlass(in: Rectangle())
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { menu } }
            .sheet(isPresented: $isPromoting) {
                if let promoting {
                    PromoteListSheet(model: model, list: promoting) { undo = $0 }
                }
            }
            .alert(
                Text("library.bulk.download.none", bundle: .module),
                isPresented: $isAllOnDevice
            ) {
                Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            }
            .confirmationDialog(
                Text("library.bulk.download.title \(pending?.ids.count ?? 0)", bundle: .module),
                isPresented: Binding(
                    get: { pending != nil },
                    set: { if !$0 { pending = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button {
                    let ids = pending?.ids ?? []
                    Task { offer(.kept, await model.keepOffline(ids)) }
                } label: {
                    Text("library.bulk.download", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            } message: {
                Text(
                    "library.bulk.download.size \((pending?.bytes ?? 0).formatted(.byteCount(style: .file)))",
                    bundle: .module
                )
            }
    }

    @ViewBuilder
    private var menu: some View {
        Menu {
            Button {
                Task { offer(.read(true), await model.mark(selection: members, read: true)) }
            } label: {
                Label {
                    Text("library.mark.read", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            Button {
                askToDownload()
            } label: {
                Label {
                    Text("library.bulk.download", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            }
            promote
        } label: {
            Label {
                Text("shelves.bulk", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .disabled(members.isEmpty)
    }

    /// The offer to put this list on a server, and the reason when there is none to put it on.
    ///
    /// `collections-and-reading-lists` offers to copy a local list to a server. Disabled with
    /// the reason beside it rather than hidden: a reader who cannot find the action does not
    /// learn that their server is unreachable, they learn that the app cannot do it.
    @ViewBuilder
    private var promote: some View {
        if let promoting, promoting.origin == .local {
            Divider()
            Button {
                isPromoting = true
            } label: {
                Label {
                    Text("shelves.promote", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.up.circle")
                }
            }
            .disabled(model.listCapableServers.isEmpty)

            if model.listCapableServers.isEmpty {
                Text("shelves.promote.unavailable", bundle: .module)
            }
        }
    }

    /// Works out what a download would copy, and either asks or says there is nothing to do.
    private func askToDownload() {
        let ids = BulkSelection.downloading(members, onDevice: model.keptOffline)
        if ids.isEmpty { isAllOnDevice = true } else { pending = (ids, model.bytesOnDisk(of: ids)) }
    }

    /// Offers an undo only when there was a change. A bar reporting nought would be a bar
    /// asking to reverse something that did not happen.
    private func offer(_ kind: BulkUndo.Kind, _ changed: Set<String>) {
        guard !changed.isEmpty else { return }
        undo = BulkUndo(kind: kind, ids: changed)
    }
}

extension View {
    /// Download and mark-read, for everything a shelf holds — and, for a local reading list,
    /// the offer to copy it onto a server.
    func shelfBulkActions(
        model: LibraryModel,
        members: Set<String>,
        promoting: ReadingList? = nil
    ) -> some View {
        modifier(ShelfBulkActions(model: model, members: members, promoting: promoting))
    }
}
