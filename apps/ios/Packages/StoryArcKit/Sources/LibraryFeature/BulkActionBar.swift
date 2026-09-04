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

    /// The actions, and the width at which each gives up its word.
    ///
    /// **The old design offered one row twice — every name or no name — and a phone always got
    /// no name.** Three names at `.controlSize(.large)` need more than the 338 pt this capsule
    /// is offered (402 − 2 × gutter − 2 × md), so `ViewThatFits` took the `.iconOnly` branch at
    /// the **default** text size, not only at the accessibility sizes as the comment here used
    /// to claim. Photographed on 2026-09-04: three bare glyphs in every frame. The library's
    /// toolbar had been cut from six unlabelled glyphs to two controls and two named menus the
    /// day before this shipped, and this surface quietly put three back one screen over.
    ///
    /// It also broke a sentence this change had already written. `native-experience`'s *Every
    /// action names itself* requires that a glyph standing alone be "one whose meaning the
    /// platform already establishes, **not one chosen to save room**" — and a `ViewThatFits`
    /// fallback is a room-saving mechanism by construction. Two of the three glyphs failed the
    /// first half as well; see ``markRead`` and ``more``.
    ///
    /// So the tiers degrade by *control* rather than by label style, and no tier draws a glyph
    /// that is not established on this screen:
    ///
    /// | tier | draws | taken at |
    /// | --- | --- | --- |
    /// | 1 | `⬇ Download`  `✓ Mark as read`  `⋯` | wide windows and iPad |
    /// | 2 | `⬇`  `✓ Mark as read`  `⋯` | a phone at the default size, in all four languages |
    /// | 3 | `⬇`  `⋯` | the accessibility sizes |
    ///
    /// Tier 2 is the one that matters, and German is what sets it: *Als gelesen markieren* is
    /// 21 characters against *Mark as read*'s 12, so a design that fits in English and not in
    /// German ships broken to a German reader. Measured widths at the default size leave every
    /// language clear of 338 pt, because only one name is drawn.
    ///
    /// **Tier 3 loses no action.** Mark-as-read is `AddToShelfMenu`'s own first row, so at the
    /// width where its button goes it is still reachable and still named — which is the whole
    /// reason ``more`` holds the complete set rather than the leftovers.
    ///
    /// A name never survives only as an accessibility label: a `Label` keeps its title whatever
    /// the style draws, so VoiceOver was correct throughout. This was always a legibility
    /// defect for a sighted reader, and no host test could see it —
    /// `BulkSelectionChromeTests` greps for `.titleAndIcon` and proves the named row is
    /// *declared*, never which branch a device takes. That took a screenshot, which is why the
    /// assertion and the captures are both required rather than either standing alone.
    @ViewBuilder
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            row(.everything)
            row(.markReadOnly)
            row(.nothing)
        }
        // All of them go inert when nothing is picked — an action on nothing would silently do
        // nothing, and the download would put up a confirmation naming nought items. They are
        // shown rather than hidden, and that was the question worth asking: a capsule arriving
        // on the first pick would be floating chrome appearing under a thumb that is mid-tap,
        // and it would change the shelf's bottom inset in the middle of a scroll. Shown and
        // inert it says what the mode is for before anything is picked, and the way out is in
        // the navigation bar throughout, so it strands nobody.
        //
        // On the `ViewThatFits` rather than inside a row, so every tier inherits it and a
        // fourth tier cannot be added without it.
        .disabled(selection.ids.isEmpty)
        // On glass, so the material decides — ``SwiftUI/View/storyArcGlassText(_:)`` says
        // why, and says it about a fixed colour that had been sitting on this very surface.
        // Covers pass under this capsule and its luminance is whichever one is passing.
        .storyArcGlassText(.primary)
        // **And the dimming is ours, because the line above took the system's away.**
        // `.disabled` normally dims a control by lowering its foreground; an explicit
        // `foregroundStyle` after it wins, so the inert capsule came out **pixel-identical**
        // to the live one — 0 differing pixels across all four appearance and text-size pairs.
        // Measured again on 2026-09-04 with this line in place: the glyph strokes go from
        // `rgb(0,0,0)` to `rgb(148,146,146)` in light at the default size, which is exactly
        // what `0.4 × 0 + 0.6 × 245` predicts against the glass ground, and the four pairs now
        // differ by 3 100, 3 084, 26 426 and 26 407 pixels. Android had the same defect from
        // the mirror-image cause — an `Icon` tint overriding `IconButton`'s `LocalContentColor`
        // — so the rule is one rule: state the colour where the control can still take it away.
        //
        // The condition is deliberately the same expression as `.disabled`'s rather than a
        // second reading of the same state: two conditions is how one of them ends up
        // inverted. `BulkSelectionChromeTests` asserts they are the same text, and in order.
        .opacity(selection.ids.isEmpty ? Self.inertOpacity : 1)
        // Large, which is the scale the system draws floating chrome at and the scale
        // `ReaderChrome` uses for the same reason: a control with no bar to sit in has to
        // carry its own presence. Not the lever for the width problem above, either: the
        // glyphs measure 18.6 pt inside a 34.3 pt capsule and there is no `.buttonStyle` here,
        // so a smaller control size buys a few points and costs the tap target.
        .controlSize(.large)
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.sm)
    }

    /// Which of the row's controls draw their name at this width.
    ///
    /// A tier per answer rather than one row restyled, because the narrowest tier also drops a
    /// control — and `.labelStyle` on the `HStack` is what made the old design all-or-nothing
    /// across three labels.
    private enum Naming { case everything, markReadOnly, nothing }

    @ViewBuilder
    private func row(_ naming: Naming) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            switch naming {
            case .everything:
                download.labelStyle(.titleAndIcon)
                markRead.labelStyle(.titleAndIcon)
            case .markReadOnly:
                download.labelStyle(.iconOnly)
                markRead.labelStyle(.titleAndIcon)
            case .nothing:
                download.labelStyle(.iconOnly)
            }
            more.labelStyle(.iconOnly)
        }
    }

    /// Download, whose glyph the platform has established well enough to stand alone.
    ///
    /// A downward arrow in a ring is the system's download mark in the App Store, Podcasts,
    /// Music, Books, Files and Photos, and on a shelf that is selecting there is nothing else a
    /// down arrow could mean.
    private var download: some View {
        Button {
            askToDownload()
        } label: {
            Label {
                Text("library.bulk.download", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
        }
    }

    /// Mark as read — **the one that keeps its word for as long as any word fits.**
    ///
    /// `checkmark.circle` is a well-established glyph in general and is not established *here*:
    /// forty points above this capsule, the picked covers carry a filled disc with a white
    /// check and the unpicked carry an empty ring, so a ring-with-a-check in the same frame is
    /// the visual union of the two selection states. One symbol, two meanings, one screen. It
    /// compounds: of the three actions this is the only one that writes state, and it is the
    /// one drawn with the most confusable mark.
    private var markRead: some View {
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

    /// Everything, behind the one glyph iOS has established for exactly this.
    ///
    /// **`text.badge.plus` used to be the row's first control and it should never have been.**
    /// Magnified it reads as a plus badge on ruled lines — *add a line*, *new note*. Apple does
    /// use it for *Add to Playlist*, but always as a named row inside a menu and never bare in
    /// a toolbar; and the action opens a chooser rather than doing something, which on this
    /// platform wants a name. Android reached the same verdict about the same glyph from its
    /// own side, which is a shared *rule* rather than shared UI: a glyph stands alone only
    /// where the platform has established it.
    ///
    /// Holding the whole set is what lets the narrowest tier drop a control without losing an
    /// action: `AddToShelfMenu` already draws mark-as-read as its first row, so at the width
    /// where the button goes the action is still here, named.
    ///
    /// `detail.more` rather than a key of its own: it already reads *More actions* in all four
    /// languages, and a second key holding the same four strings is the same trade as a hex
    /// typed twice.
    private var more: some View {
        Menu {
            // The same menu a long press on one cover opens, handed the whole set.
            AddToShelfMenu(
                model: model,
                publications: picked,
                onRefused: { refusedServer = $0 },
                onChange: { offer($0) }
            )
            download
        } label: {
            Label {
                Text("detail.more", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis")
            }
        }
    }

    /// How far the inert actions are dimmed, given the system's own dimming does not reach them.
    ///
    /// Matches what `.disabled` draws on a control that has not overridden its foreground —
    /// low enough to read as unavailable at a glance, high enough that the three names are
    /// still legible, which is what makes a shown-and-inert capsule say what the mode is for.
    private static let inertOpacity: Double = 0.4

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
