internal import SwiftUI

internal import DesignSystem

// What the library's toolbar holds — and, as much, what it no longer holds.
//
// It held seven `.primaryAction` items on an iPhone, in one undifferentiated pill:
// scope, select, layout, sort, filter, add-books, shelves and settings, six of them
// drawn as an unlabelled glyph with nothing to say which of them belonged together.
// Apple's own rule is to group items that affect the same part of the interface, so
// there are three groups now, separated by `ToolbarSpacer`:
//
//   [Select]  ·  [Layout · Sort · Filter · Scope]  ·  [Add books]
//
// **Settings and Shelves left the toolbar.** Neither is something done *to* the shelf,
// which is the only thing this bar is for. Settings is the trailing item of the home
// destination's navigation bar; Shelves is a row on the same surface. Add-books stays,
// for now and against the direction's end state: it is the only way to add a source on
// iOS, the two places the direction moves it to — the rebuilt empty state and Settings'
// connected-libraries screen — are later slices, and moving it before they exist would
// leave a reader with a populated library no way to add a second source at all.

extension LibraryView {

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        if !model.publications.isEmpty {
            // The way in. The way out is in the bar the selection puts up, so the toolbar
            // does not gain a control that is only ever half useful.
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
                .disabled(selection.isActive)
            }

            // Selecting is a mode you enter; the three below change what the shelf shows
            // while you stay where you are. Two different parts of the interface, so two
            // capsules rather than one row of six glyphs.
            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                LayoutToggle(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                SortMenu(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                FilterMenu(model: model)
            }
            // `library-browsing`: one library over every configured source, "and a way to
            // narrow it to one". Beside the filters rather than first in the bar, because
            // that is what it is — the last per-source control on the shelf, and the slice
            // that turns the scope axis from origin into availability is where it stops
            // being a mode and becomes one filter among the others.
            if !ScopeMenu.offered(in: model.registry).isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ScopeMenu(model: model)
                }
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        // A menu rather than a button per kind: there are four ways to add a source, and
        // a toolbar with one button each would crowd out the controls a reader uses every
        // day.
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isPickingFolder = true
                } label: {
                    Label {
                        Text("library.addFolder", bundle: .module)
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                Button {
                    isAddingCatalogue = true
                } label: {
                    Label {
                        Text("catalogue.title", bundle: .module)
                    } icon: {
                        Image(systemName: "dot.radiowaves.up.forward")
                    }
                }
                Button {
                    isAddingKavita = true
                } label: {
                    Label {
                        Text("kavita.title", bundle: .module)
                    } icon: {
                        Image(systemName: "externaldrive.connected.to.line.below")
                    }
                }
                Button {
                    isAddingShare = true
                } label: {
                    Label {
                        Text("smb.title", bundle: .module)
                    } icon: {
                        Image(systemName: "externaldrive.badge.wifi")
                    }
                }
            } label: {
                Label {
                    Text("library.addSource", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
