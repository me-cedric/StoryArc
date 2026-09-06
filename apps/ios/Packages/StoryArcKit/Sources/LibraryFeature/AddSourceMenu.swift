internal import SwiftUI

internal import StoryArcCore

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
            item(.localFolder, addFolder)
            ImportPublicationButton(action: importFile)
            item(.opdsCatalog, addCatalogue)
            item(.kavitaServer, addKavita)
            item(.networkShare, addShare)
        } label: {
            Label {
                Text("library.addSource", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
    }

    /// One kind of place, named and explained.
    ///
    /// `sources` asks for "a one-line explanation of each", and the live delta puts that
    /// naming here rather than on the first screen — this menu is the secondary action, and
    /// choosing between the four is the question it asks. The sentences were written and
    /// translated into four languages and drawn by nobody: the rows used to carry the four
    /// *sheets'* titles, which name the destination and say nothing about what it is.
    ///
    /// A second `Text` in a menu button's label is how SwiftUI draws a subtitle, which is the
    /// platform's own shape for exactly this. The kind carries both keys and the symbol, from
    /// ``SourceKind`` in `SourcePresentation.swift`, so a fifth kind is named everywhere at
    /// once rather than in whichever menu was remembered.
    @ViewBuilder
    private func item(_ kind: SourceKind, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(kind.titleKey, bundle: .module)
            Text(kind.explanationKey, bundle: .module)
            Image(systemName: kind.symbolName)
        }
    }
}
