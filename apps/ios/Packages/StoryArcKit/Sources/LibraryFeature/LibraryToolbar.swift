internal import SwiftUI

// What the library's toolbar holds — and, as much, what it no longer holds.
//
// It held seven `.primaryAction` items on an iPhone, in one undifferentiated pill: scope,
// select, layout, sort, filter, add-books, shelves and settings, six of them drawn as an
// unlabelled glyph with nothing to say which of them belonged together. Settings and Shelves
// went first: neither is something done *to* the shelf, which is the only thing this bar is
// for. Settings is the trailing item of the home destination's navigation bar; Shelves is a
// row on the same surface.
//
// **Six were still too many, and a design review said so.** It called them "five unlabelled
// icons"; there were six, and `LibraryToolbarTests` proved the count before anything moved.
// `library-browsing` now asks that the choices a reader makes about the shelf — "what is
// shown, how it is grouped, how it is sorted, what is filtered out" — be "reached through
// named menus rather than as separate unlabelled buttons". So there are four items in three
// groups, separated by `ToolbarSpacer`:
//
//   [Select]  ·  [View · Filter]  ·  [Add books]
//
// **The availability selector and the layout toggle folded into `ViewMenu`**, which is what
// `SortMenu` became when it stopped being only about sorting. Nothing was dropped doing it:
// every choice those two controls offered is a named picker inside that menu, and
// `LibraryToolbarTests` asserts each one is still decided somewhere rather than merely gone
// from here.
//
// **Select stays on its own, and the reason is the rule rather than its importance.** It
// changes the surface's *mode* — every cover becomes a checkbox and the shelf stops being a
// shelf — where the other three present a choice and leave. A mode switch inside a menu of
// choices is how a reader goes looking for a sort and comes back holding a checklist, which
// is why `library-browsing` allows exactly this kind of control to stand alone.
//
// **Add-books stays too, and for a different reason again**: it is not a view choice at all.
// It is the only way to add somewhere to read from on iOS, and the two places the design
// direction moves it to — the rebuilt empty state and Settings' connected-libraries screen —
// are later slices. Moving it before they exist would leave a reader with a populated library
// no way to add a second one.
//
// **While a selection is running the bar holds one item: the way out.** *Select* used to
// stay mounted-and-disabled through the mode, on the argument that a control should not move
// while a reader is using it — and the way out was an item inside the selection's own bottom
// bar. Both halves of that were wrong, and they were wrong together: it left a dead control
// beside the live ones, and it put the exit at the foot of the screen where no Apple app
// puts it. *Select* and *Done* are one switch in one slot now, which is what Photos, Files
// and Mail all do; the three view choices stand down for the duration, because none of them
// is a thing done to a *selection* and changing what the shelf shows mid-pick would carry
// picks off the screen. `BulkSelectionChromeTests` pins the swap.

extension LibraryView {

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        if selection.isActive {
            // The way out, at the trailing edge, which is where a reader's eye already goes
            // to leave a mode. `.confirmationAction` rather than a placement spelled out by
            // position: leaving is what this item semantically *is*, and the platform is
            // what knows which edge that lands on in a given language and layout.
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    selection.end()
                } label: {
                    Text("library.select.done", bundle: .module)
                }
            }
        } else {
            if !model.publications.isEmpty {
                // The way in, in the slot the way out will take over.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selection.begin()
                    } label: {
                        Label {
                            Text("library.select", bundle: .module)
                        } icon: {
                            Image(systemName: "checklist")
                        }
                    }
                }

                // Selecting is a mode you enter; the two below change what the shelf shows
                // while you stay where you are. Two different parts of the interface, so two
                // capsules rather than one row of glyphs.
                ToolbarSpacer(.fixed, placement: .primaryAction)

                // How the shelf is drawn: what is shown, how it is laid out, how it is
                // ordered. Always offered, unlike the source selector it descends from —
                // availability is a question every library can answer, including one with a
                // single folder in it.
                ToolbarItem(placement: .primaryAction) {
                    ViewMenu(model: model, availability: $availability)
                }
                // What is left out of it, which is a different question from how it is drawn.
                ToolbarItem(placement: .primaryAction) {
                    FilterMenu(model: model, downloads: $downloads, availability: $availability)
                }

                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            // `AddSourceMenu` rather than a menu hand-built here. There were two of them,
            // and the one mounted was a row short: it omitted the import, so the only way a
            // file reached StoryArc on iOS was the system's own Open-in handler.
            ToolbarItem(placement: .primaryAction) {
                AddSourceMenu(
                    addFolder: { isPickingFolder = true },
                    importFile: { isImporting = true },
                    addCatalogue: { isAddingCatalogue = true },
                    addKavita: { isAddingKavita = true },
                    addShare: { isAddingShare = true }
                )
            }
        }
    }
}
