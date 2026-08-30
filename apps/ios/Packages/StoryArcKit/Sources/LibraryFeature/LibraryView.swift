public import SwiftUI

internal import DesignSystem
public import Persistence
internal import Catalogue
internal import UniformTypeIdentifiers
public import StoryArcCore

/// The library, on whichever of the shell's surfaces is asking for it.
///
/// One view for three of them, because they are one screen over three sets: the whole
/// shelf, the part of it this device can open with no network, and the same shelf
/// narrowed by what the reader typed. ``LibrarySurface`` is the only thing that differs,
/// and it differs in what is listed and what chrome is put on top — never in the cell,
/// the grid or the way in to a reader.
///
/// It no longer builds its own split navigation. The shell above it is a `TabView` with
/// `.sidebarAdaptable`, so the platform draws the tab bar on a phone and the sidebar on
/// an iPad from the *same* three destinations; a `NavigationSplitView` here would be a
/// second, disagreeing navigation inside one of them.
public struct LibraryView: View {
    // The state below is internal rather than private because `content` and its empty
    // states live in `LibraryContent.swift`, and `private` does not reach across a file.
    // Internal, not public: nothing outside this module can see them.
    @Environment(\.theme) var theme
    @State var isPickingFolder = false
    @State var isAddingCatalogue = false
    @State var isAddingKavita = false
    @State var isAddingShare = false

    /// The catalogue being browsed, by identifier.
    ///
    /// The identifier rather than the `Source`: a navigation destination needs something
    /// `Hashable`, and a source carries a connection state that changes while the reader is
    /// inside it — which would pop the screen they are reading.
    @State var browsing: Source.ID?

    /// The term to hand a server's own search when one is opened from the library.
    @State var serverSearch = ""

    /// Which face of the library this is.
    let surface: LibrarySurface

    /// Owned by the app layer, not by this view.
    ///
    /// The app is what knows the reader was just dismissed, and a `.task` on this
    /// view does not fire again when a full-screen cover goes away — so the
    /// progress bars under the covers never updated. Whoever can observe the
    /// return has to be the one holding the model.
    let model: LibraryModel

    let onOpen: (Publication, URL) -> Void
    let progress: ProgressStore?
    /// See the initialiser. Watched rather than read: only a *change* is a request.
    let showLibrary: Int

    /// One pin set for the whole app, loaded once.
    ///
    /// Shared between adding a catalogue and browsing one on purpose: a certificate the
    /// reader accepted while adding a server has to still be accepted when its covers load.
    @State var pins: CertificatePins
    let pinStore = CertificatePinStore()
    let credentials = CredentialStore()
    let kavitaProgress = KavitaProgressStore()
    @State var smb = SmbConnection(credentials: CredentialStore())

    /// Held by the view rather than made per presentation, so a reader who dismisses the
    /// sheet mid-sign-in and reopens it finds what they typed still there.
    @State var catalogue: CatalogueConnection
    @State var kavita: KavitaConnection

    /// `onOpen` is how the app layer reaches the reader. The library knows which
    /// publication was chosen and where it lives; it does not know what a reader
    /// is.
    public init(
        model: LibraryModel,
        /// Which of the shell's surfaces this instance is drawing.
        surface: LibrarySurface = .shelf,
        progress: ProgressStore? = nil,
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in },
        /// How often the app layer has asked for the shelf itself.
        ///
        /// `navigation-shell` promises that returning to a destination is a return rather
        /// than a reset — but a quick action that names *the library* promises the shelf,
        /// not wherever the reader last was. Where this view has navigated to is `@State`,
        /// which nothing outside can reach, so the app layer changes a number and the view
        /// answers by unwinding itself.
        showLibrary: Int = 0
    ) {
        self.model = model
        self.surface = surface
        self.progress = progress
        self.showLibrary = showLibrary
        self.onOpen = onOpen

        let store = CertificatePinStore()
        let loaded = CertificatePins(store.pins())
        _pins = State(initialValue: loaded)
        _catalogue = State(
            initialValue: CatalogueConnection(
                pins: loaded,
                credentials: CredentialStore(),
                pinStore: store
            )
        )
        _kavita = State(
            initialValue: KavitaConnection(credentials: CredentialStore())
        )
    }

    /// The search text, written straight through to the query.
    ///
    /// `@Bindable` on the model would be the idiomatic shape, and it cannot be
    /// used here: the model is a `let` owned by the app layer, not state this view
    /// creates. A binding does the same job without pretending otherwise.
    var searchBinding: Binding<String> {
        Binding(get: { model.query.search }, set: { model.query.search = $0 })
    }

    /// Where a publication lives, handed to the app layer.
    func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }

    /// What the reader has picked, when they are picking.
    ///
    /// Held here rather than in either layout: a reader may switch between the grid and the
    /// list mid-selection and should not lose what they picked.
    @State var selection = LibrarySelection()

    public var body: some View {
        NavigationStack {
            libraryColumn
                .navigationDestination(item: $browsing) { id in
                    if let source = model.registry[id] { browser(for: source) }
                }
                .publicationDetail(model: model, onOpen: onOpen)
                .publicationDetail(model: model, onOpen: onOpen)
        }
        // The shelf, asked for by name.
        .onChange(of: showLibrary) { _, _ in browsing = nil }
        // `local-library`: a folder picked here is reachable again after a restart,
        // which is what the security-scoped bookmark in the model is for.
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let folder = urls.first {
                model.addFolder(folder)
            }
        }
        .sheet(isPresented: $isAddingCatalogue) {
            CatalogueSheet(connection: catalogue) { model.add($0) }
        }
        .sheet(isPresented: $isAddingKavita) {
            KavitaSheet(connection: kavita) { model.add($0) }
        }
        .sheet(isPresented: $isAddingShare) {
            SmbSheet(connection: smb) { model.add($0) }
        }
    }

    /// The way in to one source, wherever it is being shown from.
    ///
    /// Not reachable from the shelf any more, and deliberately so: a configured server is
    /// not a place to go. It is reached from search, which is the tier `library-browsing`
    /// calls *reachable* — everything a server has that the app has not cached.
    func browser(for source: Source) -> some View {
        SourceBrowser(
            source: source,
            pins: pins,
            credentials: credentials,
            kavitaProgress: kavitaProgress,
            lists: model.serverLists,
            onOpen: onOpen,
            // Carried in so the server is asked the question the reader already typed,
            // rather than being opened at its list of libraries with an empty field.
            searching: serverSearch,
            onRetry: { await model.test(source) }
        )
    }

    /// The library itself: the grid or the list, and the chrome that belongs to it.
    var libraryColumn: some View {
        searching(content)
            .navigationTitle(title)
            .toolbar { if surface == .shelf { toolbarItems } }
            // Reloaded on every appearance, which is what makes the bar under a
            // cover reflect the page the reader just reached.
            .task {
                model.restoreFolders()
                await model.refreshProgress()
                await model.probeNetworkSources(credentials: credentials, pins: pins)
                // And keeps asking while anything is away, per `sources`' backoff. After
                // the probe rather than beside it: the loop stops as soon as nothing is
                // unreachable, so started before the first answer it would stop before
                // there was one.
                await model.retryUnreachableSources(credentials: credentials, pins: pins)
            }
            // `local-library`'s "reconciles ... after files changed": a provider notifies
            // nobody while the app is away. Android does the same on `ON_RESUME`.
            .watchingFolders(of: model)
            // `sources` names pull-to-refresh: a refresh "re-fetches the catalogue in the
            // background" and updates the view "incrementally rather than clearing it".
            .refreshable {
                await model.probeNetworkSources(credentials: credentials, pins: pins)
                await model.rescan()
            }
            // A bar, so the notice floats on glass and the shelf fades out beneath it
            // rather than being clipped by it. Above the tab bar, which the system insets
            // for — the reason cover titles used to render *behind* the floating search
            // pill is that there was no tab bar for it to inset against.
            .safeAreaBar(edge: .bottom) {
                if selection.isActive {
                    BulkActionBar(model: model, selection: $selection)
                } else if let missing = model.unavailableFolders.first {
                    // Named, per `local-library`. "A folder is no longer available"
                    // sends someone hunting through four of them.
                    UnavailableFolderNotice(name: missing) { isPickingFolder = true }
                } else if case let .finished(found, skipped) = model.scanState, skipped > 0 {
                    // Stated once, at the end, rather than per file — a messy
                    // folder would otherwise be a wall of notices. But stated:
                    // a count that silently omits what it could not read is a lie.
                    ScanSummary(found: found, skipped: skipped)
                }
            }
    }

    /// What the navigation bar calls this surface.
    var title: Text {
        switch surface {
        case .shelf: Text("library.title", bundle: .module)
        case .onDevice: Text("library.downloads.title", bundle: .module)
        case .search: Text("library.search.prompt", bundle: .module)
        }
    }
}

extension LibraryView {
    /// The field, and only on the surface that owns one.
    ///
    /// The shelf has no field at all now. Search is a destination the shell offers with
    /// `Tab(role: .search)` — the system's own control, set apart from the three
    /// destinations, expanding into a field and taking the rest of the bar with it. A
    /// second field on the shelf was the floating pill that cover titles were rendering
    /// behind, and `navigation-shell` asks for search to be reached one way, not two.
    @ViewBuilder
    func searching(_ inner: some View) -> some View {
        if surface == .search {
            inner
                .searchable(
                    text: searchBinding,
                    prompt: Text("library.search.prompt", bundle: .module)
                )
                // `library-browsing`: "when a user opens search, recent queries are
                // offered". Written and translated on both platforms; this modifier was
                // the missing half, so no iOS reader had ever seen one.
                .searchSuggestions { RecentSearchSuggestions(model: model) }
        } else {
            inner
        }
    }
}
