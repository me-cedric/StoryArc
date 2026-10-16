import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// The library window: a sidebar of the destination set, and the content column.
///
/// The sidebar lists `LibraryDestination.allCases`, in the order the enum fixes, so the Mac
/// offers exactly the four places iOS and Android offer and no row per source. Below them
/// the Library group of the design's section 2, as filters of the shelf. The shelves group
/// is wave 3.
///
/// Search is the toolbar field the design asks for: it stays in place, and its results take
/// the content column while text is in it (`SearchState`).
struct LibraryWindow: View {
    static let id = "library"
    /// The documented minimum (`desktop-experience`, *Any window size*). Below about 600
    /// points the system collapses the sidebar into its toggle, as the design expects.
    static let minimumSize = CGSize(width: 640, height: 440)

    let library: MacLibrary

    @State private var selection: SidebarRow? = .destination(.home)
    @State private var search = SearchState()
    @State private var path = NavigationPath()
    @State private var libraryFilter: LibraryShelfFilter = .all
    @State private var gridSelection = LibrarySelection()
    @State private var isSearchFocused = false
    @State private var showingFolderOffer = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                LibraryContentColumn(
                    library: library, search: search, destination: current,
                    filter: libraryFilter, selection: $gridSelection,
                    onOpen: open, onShow: { path.append(PublicationRoute($0)) }
                )
                .navigationTitle(current.title)
                .navigationDestination(for: PublicationRoute.self) { route in
                    // Re-read from the model on every redraw, as `PublicationRoute` asks.
                    if let publication = library.model.publications.first(where: { $0.id == route.publicationID }) {
                        DetailView(library: library, publication: publication, onOpen: open)
                    }
                }
            }
            .toolbar { LibraryToolbarMenus(model: library.model) }
        }
        .searchable(
            text: searchText, isPresented: $isSearchFocused, placement: .toolbar,
            prompt: Text("desktop.search.prompt")
        )
        .focusedSceneValue(\.libraryActions, actions)
        .onChange(of: selection) { _, row in
            if case let .destination(destination) = row { search = search.moved(to: destination) }
            if case let .filter(filter) = row { libraryFilter = filter; search = search.moved(to: .library) }
            path = NavigationPath()
        }
        .onChange(of: FileInbox.shared.serial) { Task { await library.openHandedOver { openWindow.reader($0) } } }
        .onChange(of: library.navigationRequest) { _, request in
            guard let request else { return }
            library.navigationRequest = nil
            navigate(request)
        }
        .onChange(of: library.offeredFolder) { showingFolderOffer = library.offeredFolder != nil }
        .acceptsDroppedFiles()
        .confirmationDialog(
            Text("desktop.drop.folder.title \(library.offeredFolder?.lastPathComponent ?? "")"),
            isPresented: $showingFolderOffer, titleVisibility: .visible
        ) {
            Button {
                if let folder = library.offeredFolder { library.addFolder(folder) }
                library.offeredFolder = nil
            } label: {
                Text("desktop.drop.folder.add")
            }
            Button(role: .cancel) { library.offeredFolder = nil } label: { Text("desktop.drop.folder.cancel") }
        } message: {
            Text("desktop.drop.folder.body")
        }
        .task {
            WindowOpener.shared.openReader = { openWindow.reader($0) }
            WindowOpener.shared.openLibrary = { openWindow(id: Self.id) }
            await library.restore()
            for session in library.restorableReaders() { openWindow.reader(session.target) }
            await library.openHandedOver { openWindow.reader($0) }
        }
    }

    private var current: LibraryDestination {
        switch selection {
        case let .destination(destination): destination
        case .filter: .library
        case nil: .home
        }
    }

    private var searchText: Binding<String> {
        Binding(get: { search.text }, set: { search = $0.isEmpty ? search.cleared() : search.typed($0) })
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(LibraryDestination.allCases) { destination in
                Label(destination.title, systemImage: destination.symbolName)
                    .tag(SidebarRow.destination(destination))
            }
            Section("desktop.sidebar.libraryGroup") {
                ForEach(LibraryShelfFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.symbolName)
                        .tag(SidebarRow.filter(filter))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        // The sidebar draws its own row font; the reader's text size reaches it through the
        // system's own row sizes.
        .environment(\.sidebarRowSize, MacSettings.shared.textSize == .default ? .medium : .large)
    }

    private var actions: LibraryActions {
        LibraryActions(
            openFile: { Task { for target in await library.chooseFile() { openWindow.reader(target) } } },
            addFolder: { library.chooseFolder() },
            refresh: { Task { await library.model.rescan() } },
            find: { isSearchFocused = true },
            viewAsGrid: { library.model.layout = .grid },
            viewAsList: { library.model.layout = .list },
            go: { go($0) },
            continueReading: {
                if let first = library.model.continueReading.first { open(first) }
            },
            showDetails: {
                if let id = gridSelection.ids.first {
                    path.append(PublicationRoute(publicationID: id))
                }
            }
        )
    }

    private func go(_ place: LibraryGo) {
        switch place {
        case .home: selection = .destination(.home)
        case .library: selection = .destination(.library)
        case .downloads: selection = .destination(.onDevice)
        }
    }

    private func navigate(_ request: LibraryNavigation) {
        switch request {
        case let .go(place): go(place)
        case let .search(text): search = text.isEmpty ? search.cleared() : search.typed(text)
        case let .details(id): path.append(PublicationRoute(publicationID: id))
        }
    }

    private func open(_ publication: Publication) {
        guard let target = library.target(for: publication) else { return }
        library.recents.note(target)
        openWindow.reader(target)
    }

}

/// A row of the sidebar: one of the four destinations, or a filter of the library.
enum SidebarRow: Hashable {
    case destination(LibraryDestination)
    case filter(LibraryShelfFilter)
}

/// The Library group of the design's section 2: filters of the one shelf.
enum LibraryShelfFilter: String, CaseIterable, Identifiable, Hashable {
    case all, series, recentlyAdded

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "desktop.sidebar.allBooks"
        case .series: "desktop.sidebar.series"
        case .recentlyAdded: "desktop.sidebar.recentlyAdded"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .series: "rectangle.stack"
        case .recentlyAdded: "clock"
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
