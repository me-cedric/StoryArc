internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What can be done to everything the reader has picked.
///
/// `collections-and-reading-lists` wants a selection added to a collection or a list,
/// downloaded, and marked read — and the mark "undoable for 10 seconds". Every one of these
/// is the single-publication path applied to a set: ``AddToShelfMenu`` is the same menu a
/// long press opens, the mark is the same mark, and the copy is the same one the app makes
/// when a share goes away.
///
/// Along the foot of the library, where a thumb is, and where the count stays visible while
/// the reader keeps picking.
struct BulkActionBar: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    @Binding var selection: LibrarySelection

    /// The last action, until its ten seconds are up.
    @State private var undo: BulkUndo?
    @State private var refusedServer: String?
    /// Set when a download would copy nothing, because it is all here already.
    @State private var isAllOnDevice = false

    /// What the download would copy and what it weighs, once the reader has asked.
    ///
    /// Worked out on the tap rather than on every redraw: both halves read the download
    /// store off disk, and a computed property would do that on each pass over the bar.
    @State private var pending: (ids: Set<String>, bytes: Int64)?

    var body: some View {
        VStack(spacing: 0) {
            if let undo {
                BulkUndoBar(record: undo, model: model) { self.undo = nil }
            }
            actions
        }
        .storyArcGlass(in: Rectangle())
        .alert(
            Text("shelves.serverOnly.title", bundle: .module),
            isPresented: Binding(
                get: { refusedServer != nil },
                set: { if !$0 { refusedServer = nil } }
            )
        ) {
            Button(role: .cancel) { refusedServer = nil } label: {
                Text("shelves.cancel", bundle: .module)
            }
        } message: {
            Text("shelves.serverOnly.body \(refusedServer ?? "")", bundle: .module)
        }
        .alert(
            Text("library.bulk.download.none", bundle: .module),
            isPresented: $isAllOnDevice
        ) {
            Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
        }
        // `offline-downloads`: the app "states the item count and total size and asks for
        // confirmation before queueing them". Both, before anything is copied.
        .confirmationDialog(
            Text("library.bulk.download.title \(pending?.ids.count ?? 0)", bundle: .module),
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button {
                Task { await download() }
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
    private var actions: some View {
        HStack(spacing: StoryArcSpace.md) {
            Text("library.selected \(selection.count)", bundle: .module)
                .textRole(.footnote)
                // On glass, so the material decides — see ``ScanSummary``. This bar floats
                // over the shelf with covers passing beneath it, exactly like that one.
                .storyArcGlassText()

            Spacer(minLength: 0)

            Group {
                Menu {
                    // The same menu a long press on one cover opens, handed the whole set.
                    AddToShelfMenu(
                        model: model,
                        publications: picked,
                        onRefused: { refusedServer = $0 },
                        onChange: { offer($0) }
                    )
                } label: {
                    Label {
                        Text("shelves.addTo", bundle: .module)
                    } icon: {
                        Image(systemName: "text.badge.plus")
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

                Button {
                    Task { await markRead() }
                } label: {
                    Label {
                        Text("library.mark.read", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
            // The three actions go at once when nothing is picked, and only those three: an
            // action on nothing would silently do nothing, but a way out that came and went
            // with the selection would strand a reader who picked nothing.
            .disabled(selection.ids.isEmpty)

            // The way out. One action: it leaves the mode and drops the picks together,
            // because a reader who has finished picking has finished with both.
            Button {
                selection.end()
            } label: {
                Text("library.select.done", bundle: .module)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
    }

    private var picked: [Publication] {
        model.publications.filter { selection.contains($0.id) }
    }

    private func markRead() async {
        let changed = await model.mark(selection: selection.ids, read: true)
        offer(BulkUndo(kind: .read(true), ids: changed))
    }

    /// Works out what a download would copy, and either asks or says there is nothing to do.
    private func askToDownload() {
        let ids = BulkSelection.downloading(selection.ids, onDevice: model.keptOffline)
        if ids.isEmpty { isAllOnDevice = true } else { pending = (ids, model.bytesOnDisk(of: ids)) }
    }

    private func download() async {
        guard let ids = pending?.ids else { return }
        let kept = await model.keepOffline(ids)
        offer(BulkUndo(kind: .kept, ids: kept))
    }

    private func offer(_ record: BulkUndo) {
        guard !record.ids.isEmpty else { return }
        undo = record
    }
}

/// The undo a bulk action leaves behind.
///
/// `collections-and-reading-lists`: the action "is undoable for 10 seconds". The ten seconds
/// are counted here rather than by whoever offered the undo, so the timer cannot outlive the
/// offer it belongs to — a stray sleep clearing a *later* offer is the bug this shape makes
/// impossible: the task is cancelled when the bar goes away or the record changes.
struct BulkUndoBar: View {
    @Environment(\.theme) private var theme

    let record: BulkUndo
    let model: LibraryModel
    /// Called when the offer is taken or its window closes. Either way it is over.
    let onSettle: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            Text("library.bulk.changed \(record.ids.count)", bundle: .module)
                .textRole(.footnote)
                // On glass, here and again in ``ShelfBulkActions``, which puts this same bar
                // over a collection's covers.
                .storyArcGlassText()

            Spacer(minLength: 0)

            Button {
                Task {
                    await model.undo(record)
                    onSettle()
                }
            } label: {
                Text("library.bulk.undo", bundle: .module)
                    .textRole(.footnote)
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .task(id: record.id) {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            onSettle()
        }
    }
}
