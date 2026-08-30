internal import SwiftUI

/// The five ways to bring something in to read.
///
/// A menu rather than five buttons. There are four kinds of library now and there will be
/// more; a toolbar with one button per kind would crowd out the controls a reader uses every
/// day. Android's `AddSourceMenu` is the same menu.
///
/// It was written, translated, and mounted by nothing: `LibraryToolbar` hand-built a
/// four-item menu of its own that omitted the import, so the only way a file reached
/// StoryArc on iOS was the system's own Open-in handler. Two menus for one job is how one of
/// them ends up a row short, which is exactly what happened.
struct AddSourceMenu: View {
    let addFolder: () -> Void
    /// `local-library`: a file brought in from elsewhere is copied into storage the app
    /// owns. Its own control rather than a mode of "add a folder", because a reader adding a
    /// folder is pointing at something they keep, and a reader importing is handing it over.
    let importFile: () -> Void
    let addCatalogue: () -> Void
    let addKavita: () -> Void
    let addShare: () -> Void

    var body: some View {
        Menu {
            item("library.addFolder", "folder.badge.plus", addFolder)
            ImportPublicationButton(action: importFile)
            item("catalogue.title", "dot.radiowaves.up.forward", addCatalogue)
            item("kavita.title", "externaldrive.connected.to.line.below", addKavita)
            item("smb.title", "externaldrive.badge.wifi", addShare)
        } label: {
            Label {
                Text("library.addSource", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
    }

    @ViewBuilder
    private func item(
        _ key: LocalizedStringKey,
        _ symbol: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(key, bundle: .module)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}
