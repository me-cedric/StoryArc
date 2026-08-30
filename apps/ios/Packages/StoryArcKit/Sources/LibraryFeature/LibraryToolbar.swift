internal import SwiftUI

internal import DesignSystem

// What the library's toolbar holds.
//
// Split out of `LibraryView.swift`, which had reached the 400-line cap this project
// enforces once the sidebar layout arrived. The division is the same one the file already
// makes: that file is what the library *is*, this is what can be done to it.

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
                    .labelStyle(.iconOnly)
                }
                .disabled(selection.isActive)
            }
            ToolbarItem(placement: .primaryAction) {
                LayoutToggle(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                SortMenu(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                FilterMenu(model: model)
            }
        }
        // A menu rather than a second button. There are two ways to add a
        // source now and there will be four; a toolbar with one button per kind
        // would crowd out the controls a reader uses every day.
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
        // Last, and only where there is no sidebar. A reader with an empty
        // library still needs to reach About, and `settings-and-about` puts the
        // licences there — but a wide window already shows both of these as
        // rows, and a toolbar that repeated them would be two buttons for one
        // place.
        if !windowClass.showsSidebar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ShelvesView(model: model, onOpen: onOpen)
                } label: {
                    Label {
                        Text("shelves.title", bundle: .module)
                    } icon: {
                        Image(systemName: "square.stack")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onOpenSettings) {
                    Label {
                        Text("library.settings", bundle: .module)
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}
