import DesignSystem
import LibraryFeature
import SwiftUI

/// The library window: a sidebar of the destination set, and the content column.
///
/// The sidebar lists `LibraryDestination.allCases`, in the order the enum fixes, so the Mac
/// offers exactly the four places iOS and Android offer and no row per source: the
/// `navigation-shell` promise that the set "does not change when sources are added or
/// removed" is a type the Mac imports rather than a list it keeps. The library and shelves
/// groups of the design's section 2 need a `LibraryModel`, and arrive with the data in
/// wave 2.
///
/// Search is the toolbar field the design asks for, and `desktop-experience` reads it as a
/// results view that takes the content column while text is in the field.
struct LibraryWindow: View {
    static let id = "library"
    /// The documented minimum (`desktop-experience`, *Any window size*). Below about 600
    /// points the system collapses the sidebar into its toggle, as the design expects.
    static let minimumSize = CGSize(width: 640, height: 440)

    @State private var selection: LibraryDestination? = .home
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(LibraryDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbolName)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            content
                .navigationTitle(current.title)
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("desktop.search.prompt"))
    }

    private var current: LibraryDestination { selection ?? .home }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            DestinationEmptyState(destination: current) {
                selection = .library
            }
        } else {
            // No source yet, so nothing matches. The system's own "No Results for" view, so
            // the sentence is the one every other Mac app says.
            ContentUnavailableView.search(text: query)
        }
    }
}

extension LibraryDestination {
    /// The Mac catalogue's name for each destination. `onDevice` reads *Downloads*, as on
    /// the phone's tab bar and in the design's sidebar.
    var title: LocalizedStringKey {
        switch self {
        case .home: "desktop.nav.home"
        case .library: "desktop.nav.library"
        case .onDevice: "desktop.nav.downloads"
        case .search: "desktop.nav.search"
        }
    }
}
