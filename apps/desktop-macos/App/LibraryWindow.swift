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
    /// One path per sidebar row: `navigation-shell`, *Each destination remembers where the
    /// reader had got to*, so coming back to a row returns to its page, not its root.
    @State private var paths: [SidebarRow: NavigationPath] = [:]
    @State private var libraryFilter: LibraryShelfFilter = .all
    @State private var gridSelection = LibrarySelection()
    @State private var isSearchFocused = false
    @State private var showingFolderOffer = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: path) {
                Group {
                    if case let .shelf(pin) = selection, !search.isShowingResults {
                        ShelfPage(
                            library: library, pin: pin, selection: $gridSelection, onOpen: open,
                            onShow: { path.wrappedValue.append(PublicationRoute($0)) }
                        )
                        .navigationTitle(MacShelves.name(of: pin, in: library.model.shelves) ?? "")
                    } else {
                        LibraryContentColumn(
                            library: library, search: search, destination: current,
                            filter: libraryFilter, selection: $gridSelection,
                            onOpen: open, onShow: { path.wrappedValue.append(PublicationRoute($0)) }
                        )
                        .navigationTitle(current.title)
                    }
                }
                .navigationDestination(for: PublicationRoute.self) { route in
                    // Re-read from the model on every redraw, as `PublicationRoute` asks.
                    if let publication = library.model.publications.first(where: { $0.id == route.publicationID }) {
                        DetailView(
                            library: library, publication: publication, onOpen: open,
                            onShow: { path.wrappedValue.append(PublicationRoute($0)) }
                        )
                    }
                }
            }
            // A stack per row, so a row's pushed pages are its own.
            .id(selection ?? .destination(.home))
            .safeAreaInset(edge: .bottom) { CompactPlayerBar(centre: .shared) { openWindow.reader($0) } }
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
        }
        .onChange(of: FileInbox.shared.serial) { Task { await library.openHandedOver { openWindow.reader($0) } } }
        // Task 5.9: the first rows on screen, each thousand after, then the scan done.
        .onChange(of: library.model.publications.count) { _, count in
            guard LaunchClock.isArmed, count > 0 else { return }
            DispatchQueue.main.async {
                LaunchClock.note("shelf", count: count)
                LaunchClock.note("shelf-\(count / 1000 * 1000)", count: count)
            }
        }
        .onChange(of: library.model.scanState) { _, state in
            if case .finished = state { LaunchClock.note("scanned", count: library.model.publications.count) }
        }
        .onChange(of: library.navigationRequest) { _, request in
            guard let request else { return }
            library.navigationRequest = nil
            navigate(request)
        }
        .onChange(of: library.offeredFolder) { showingFolderOffer = library.offeredFolder != nil }
        // A finished download joins the shelf as soon as it lands; no notification says so.
        .onChange(of: library.downloads.finished.count) { Task { await library.model.adoptDownloads() } }
        .acceptsDroppedFiles()
        .shelfPrompts(library) { selection = .shelf($0) }
        .shelfBulkPrompts(library)
        .restartConfirmation(library)
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
            LaunchClock.note("window", count: library.model.publications.count)
            WindowOpener.shared.openReader = { openWindow.reader($0) }
            WindowOpener.shared.openLibrary = { openWindow(id: Self.id) }
            await library.restore()
            // `desktop-experience`, *At start*: beside the window, never in front of it.
            library.sync.start {
                await library.model.reloadAfterImport()
                await library.refreshProgress()
            }
            for session in library.restorableReaders() { openWindow.reader(session.target) }
            await library.openHandedOver { openWindow.reader($0) }
        }
    }

    /// The navigation path of the row on show.
    private var path: Binding<NavigationPath> {
        let row = selection ?? .destination(.home)
        return Binding(
            get: { paths[row] ?? NavigationPath() },
            // A stack being left pops itself and writes the empty path back after the row has
            // already changed; the library walk measured it. Only the row on show may write.
            set: { new in if row == (selection ?? .destination(.home)) { paths[row] = new } }
        )
    }

    private var current: LibraryDestination {
        switch selection {
        case let .destination(destination): destination
        case .filter, .shelf: .library
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
            // The design's Shelves group: collections and reading lists, pinned first.
            Section {
                ForEach(library.shelfRows) { row in
                    Label(row.name, systemImage: row.symbolName)
                        .tag(SidebarRow.shelf(row.pin))
                        .contextMenu { ShelfRowMenu(library: library, row: row) }
                }
                NewShelfMenu()
                AllShelvesButton()
            } header: {
                Text("desktop.shelves.title")
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
            refresh: {
                Task {
                    await library.model.rescan()
                    await library.servers.refresh()
                }
            },
            find: { isSearchFocused = true },
            viewAsGrid: { library.model.layout = .grid },
            viewAsList: { library.model.layout = .list },
            go: { go($0) },
            continueReading: {
                if let first = library.model.continueReading.first { open(first) }
            },
            showDetails: {
                if let id = gridSelection.ids.first {
                    path.wrappedValue.append(PublicationRoute(publicationID: id))
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
        case let .details(id): path.wrappedValue.append(PublicationRoute(publicationID: id))
        case .root: path.wrappedValue = NavigationPath()
        case let .filter(filter): selection = .filter(filter)
        case let .shelf(pin): selection = .shelf(pin)
        case .sources:
            MacSettings.shared.settingsTab = .sources
            openSettings()
        case .finished:
            var query = library.model.query
            query.readStates = [.finished]
            library.model.query = query
            selection = .destination(.library)
        }
    }

    private func open(_ publication: Publication) {
        guard let target = library.target(for: publication) else { return }
        library.recents.note(target)
        openWindow.reader(target)
    }

}

/// A row of the sidebar: one of the four destinations, a filter of the library, or a shelf.
enum SidebarRow: Hashable {
    case destination(LibraryDestination)
    case filter(LibraryShelfFilter)
    case shelf(ShelfPin)
}

/// The one menu that makes a new shelf, as the Shelves group's last row. It sat in the
/// group's heading until macOS 26 was seen to expose a heading that holds a menu as one
/// 17-point menu button, under the audit's 20-point floor; a row is as tall as every row.
private struct NewShelfMenu: View {
    var body: some View {
        Menu {
            Button {
                ShelfPrompts.shared.naming = ShelfNaming(purpose: .create(.collection, adding: []), name: "")
            } label: { Text("desktop.shelves.newCollection") }
            Button {
                ShelfPrompts.shared.naming = ShelfNaming(purpose: .create(.list, adding: []), name: "")
            } label: { Text("desktop.shelves.newList") }
        } label: {
            Label("desktop.shelves.new", systemImage: "plus")
        }
        .menuStyle(.automatic)
        .menuIndicator(.hidden)
    }
}

/// Opens every shelf, the servers' included, in a window of its own.
private struct AllShelvesButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: AllShelvesWindow.id) } label: {
            Label("desktop.shelves.all", systemImage: "square.stack")
        }
        .buttonStyle(.plain)
    }
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
