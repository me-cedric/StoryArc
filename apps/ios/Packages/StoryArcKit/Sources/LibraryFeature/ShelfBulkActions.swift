internal import SwiftUI

internal import DesignSystem
internal import Persistence
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
    @State private var pending: BulkDownloadAsk?

    func body(content: Content) -> some View {
        content
            // A floating capsule, inset — not the full-bleed rectangle of glass that stood
            // here. It is the same ``BulkUndoBar`` the library's selection puts up, and the
            // library's is a capsule now; a slab on this surface beside a pill on that one
            // is the "two bars that do not look like the same product" the owner reported,
            // one screen over. The hard top edge was its own defect too: it cut the captions
            // of the collection's covers in half as they scrolled under it.
            .safeAreaInset(edge: .bottom) {
                if let undo {
                    BulkUndoBar(record: undo, model: model) { self.undo = nil }
                        .storyArcGlass(in: Capsule())
                        .padding(.horizontal, StoryArcSpace.gutter)
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
                    "library.bulk.download.size \(DownloadStore.formatted(pending?.bytes ?? 0))",
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

    /// The offer to put this list in an online library, and the reason when there is none
    /// to put it in.
    ///
    /// `collections-and-reading-lists` offers to copy a local list to a server, and when
    /// none is reachable "the offer to copy is disabled and says why, rather than failing
    /// after the user has confirmed it". So it is never hidden — but §3.6 of the revamp
    /// demotes it: it is a thing a reader does occasionally, not one of the things this
    /// menu is for. Hence a section of its own below the two everyday actions, and the
    /// reason as the item's own subtitle rather than as a paragraph sitting in the menu
    /// above it for every reader who has no online library at all.
    @ViewBuilder
    private var promote: some View {
        if let offer = PromoteOffer.of(promoting, servers: model.listCapableServers) {
            Section {
                Button {
                    isPromoting = true
                } label: {
                    promoteLabel(offer)
                    if offer.statesWhyNot {
                        Text("shelves.promote.unavailable", bundle: .module)
                    }
                }
                .disabled(!offer.isEnabled)
            }
        }
    }

    /// What the action calls itself.
    ///
    /// Named when there is one online library to name, which is the ordinary case: "Copy to
    /// Attic Kavita…" is a specific errand, where "Copy to an online library…" is a feature
    /// announcing itself. With two or more the generic wording is the honest one, because
    /// the choice is the next screen's.
    @ViewBuilder
    private func promoteLabel(_ offer: PromoteOffer) -> some View {
        if let named = offer.namedServer {
            Text("shelves.promote.named \(named)", bundle: .module)
        } else {
            Text("shelves.promote", bundle: .module)
        }
    }

    /// Works out what a download would copy, and either asks or says there is nothing to do.
    private func askToDownload() {
        let wanted = downloadableMembers(members, among: model.publications) {
            PublicationActions.canCopy($0, file: model.location(of: $0), model: model)
        }
        let ask = BulkDownloadAsk.of(wanted, onDevice: model.keptOffline) {
            model.bytesOnDisk(of: $0)
        }
        if let ask { pending = ask } else { isAllOnDevice = true }
    }

    /// Offers an undo only when there was a change. A bar reporting nought would be a bar
    /// asking to reverse something that did not happen.
    private func offer(_ kind: BulkUndo.Kind, _ changed: Set<String>) {
        guard !changed.isEmpty else { return }
        undo = BulkUndo(kind: kind, ids: changed)
    }
}

/// Which of a shelf's members a bulk download would actually copy.
///
/// `collections-and-reading-lists` has the app state "the item count and total size before
/// starting", and the number stated was every member this device did not already hold. Three
/// kinds of member are in that count and in no copy: a folder of images, which
/// ``LibraryModel/keepOffline(_:queue:)`` skips because there is no single file to take; a
/// publication no decoder opens; and a network share row, which that method has no road for
/// at all and leaves behind without a word. A reader was quoted sixteen titles and a size,
/// and got eleven.
///
/// ``PublicationActions/canCopy(_:file:model:)`` is the same question the single download
/// action asks, so the confirmation now counts exactly what one tap would take. A member the
/// shelf names and the library no longer holds falls out here too, for the same reason.
///
/// Free, and with the rule passed in, so ``ShelfDownloadCountTests`` can state the answer
/// without composing a view or a model. Android's `downloadableMembers` asks its own
/// `PublicationActions.canCopy`.
func downloadableMembers(
    _ members: Set<String>,
    among publications: [Publication],
    canCopy: (Publication) -> Bool
) -> Set<String> {
    Set(publications.filter { members.contains($0.id) && canCopy($0) }.map(\.id))
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
