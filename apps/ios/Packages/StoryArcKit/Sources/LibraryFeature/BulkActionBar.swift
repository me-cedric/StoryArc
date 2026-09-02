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
/// **This was a full-bleed bar and is now a floating capsule, and the difference is the
/// whole point.** It drew `storyArcGlass(in: Rectangle())` — edge to edge, with a hard top
/// edge that cut the captions of covers in half as they scrolled under it — and it held a
/// left-aligned count, three `.labelStyle(.iconOnly)` glyphs and a *Done*. It was hosted in
/// `LibraryView`'s `.safeAreaBar(edge: .bottom)` **above an untouched tab bar**, so the foot
/// of the screen showed a grey slab sitting on a rounded glass pill: two bottom bars, of two
/// shapes, that did not look like the same product. Measured on a booted iPhone 17 Pro on
/// 2026-09-02 — the last row of covers *did* clear the bar, so the inset was never the
/// defect; the shape was.
///
/// Photos, Files and Mail on iOS 26 answer a selection the same way, in three parts, and
/// only the third of them is here:
///
/// 1. **the count is the navigation title** — ``LibraryView``;
/// 2. **the way out is the toolbar's trailing item** — `LibraryToolbar.swift`;
/// 3. **the actions are a floating glass capsule that replaces the tab bar** — this file,
///    plus the one line in ``LibraryView`` that takes the tab bar down for the duration.
///
/// So what is left here is the actions and nothing else: no label to left-align, no way out
/// to put beside them, and no reason to span the width. `BulkSelectionChromeTests` pins each
/// of the three, and pins the tab bar's absence in particular.
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
        // Grouped, so the undo capsule and the actions capsule morph into one another when
        // they meet rather than stacking two edges. `DesignSystem/Glass.swift`: the
        // container is the only thing that produces that, and the modifier cannot do it
        // from inside a single surface.
        GlassEffectContainer(spacing: StoryArcSpace.sm) {
            VStack(spacing: StoryArcSpace.sm) {
                if let undo {
                    BulkUndoBar(record: undo, model: model) { self.undo = nil }
                        .storyArcGlass(in: Capsule())
                }
                actions
                    .storyArcGlass(in: Capsule())
            }
            // Inset from the edges, which is what makes it float rather than sit in a bar.
            // The capsules hug their content and the stack centres them, so the shelf still
            // shows through on both sides of the chrome.
            .padding(.horizontal, StoryArcSpace.gutter)
        }
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

    /// The three actions, named wherever the width allows.
    ///
    /// **Icon-only is what a design review objected to**, and the library's toolbar was cut
    /// from six unlabelled glyphs to two controls and two *named* menus the day before this;
    /// three bare glyphs here would repeat the mistake one surface over. So `ViewThatFits`
    /// offers the named row first and falls back to glyphs only at a width that cannot hold
    /// the names — which on a phone is the accessibility text sizes, where the fallback is
    /// doing real work. The name survives the fallback either way: a `Label` keeps its title
    /// as its accessibility label whatever the label style draws, which is exactly why these
    /// are `Label`s rather than bare `Image`s.
    @ViewBuilder
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            actionRow.labelStyle(.titleAndIcon)
            actionRow.labelStyle(.iconOnly)
        }
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.sm)
    }

    private var actionRow: some View {
        HStack(spacing: StoryArcSpace.md) {
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
        // All three go inert when nothing is picked — an action on nothing would silently do
        // nothing, and the download would put up a confirmation naming nought items. They
        // are shown rather than hidden, and that was the question worth asking: a capsule
        // arriving on the first pick would be floating chrome appearing under a thumb that
        // is mid-tap, and it would change the shelf's bottom inset in the middle of a
        // scroll. Shown and inert it says what the mode is for before anything is picked,
        // and the way out is in the navigation bar throughout, so it strands nobody.
        .disabled(selection.ids.isEmpty)
        // On glass, so the material decides — ``SwiftUI/View/storyArcGlassText(_:)`` says
        // why, and says it about a fixed colour that had been sitting on this very surface.
        // Covers pass under this capsule and its luminance is whichever one is passing.
        .storyArcGlassText(.primary)
        // Large, which is the scale the system draws floating chrome at and the scale
        // `ReaderChrome` uses for the same reason: a control with no bar to sit in has to
        // carry its own presence.
        .controlSize(.large)
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
///
/// It hugs its content rather than spanning the width, because both of the surfaces that put
/// it up now draw it as a floating capsule: the library's selection stacks it above the
/// action capsule inside one `GlassEffectContainer`, and ``ShelfBulkActions`` floats it over
/// a collection's covers. A `Spacer` between the sentence and *Undo* stood here while both
/// were full-bleed rectangles; in a capsule it stretches the pill to the screen's width for
/// no reason but its own.
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
