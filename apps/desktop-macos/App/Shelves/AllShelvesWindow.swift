import LibraryFeature
import StoryArcCore
import SwiftUI

/// Every shelf, the servers' with the Mac's own (`collections-and-reading-lists`, *Mixed listing*, *A shelf that a
/// server defines*, *Converting a local list*; `kavita-server`, *Viewing server collections*, *Adding to a server
/// reading list*, *Mixing sources in one list*): the phones' `ShelvesView` in a window of its own, so the server
/// collections and reading lists, their labels and the conversion of a local list are the phones' own screens.
struct AllShelvesWindow: View {
    static let id = "all-shelves"

    let library: MacLibrary
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            ShelvesView(model: library.model) { publication, url in
                let path = url.path(percentEncoded: false)
                let target = ReaderTarget(publicationID: publication.id, path: path, title: publication.displayTitle)
                openWindow.reader(target)
            }
        }
        .navigationTitle(Text("desktop.shelves.all"))
        .frame(minWidth: 640, minHeight: 480)
    }
}
