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
    @State var isImporting = false
    @State var isAddingCatalogue = false
    @State var isAddingKavita = false
    @State var isAddingShare = false

    /// What the shelf is narrowed to: everything, or only what opens with no network.
    ///
    /// `library-browsing` makes availability the library's primary axis and demands that the
    /// choice "persists until changed". `@AppStorage` rather than a field on `LibraryQuery`:
    /// the query is the value both platforms share and both encode, and this is one shelf
    /// choice that belongs to the iOS screen. It lands in the same `UserDefaults` the rest of
    /// the library's preferences use, under a key of its own, so nothing has to be migrated.
    @AppStorage(LibraryAvailability.storageKey)
    var availability: LibraryAvailability = .everywhere

    /// The catalogue being browsed, by identifier.
    ///
    /// The identifier rather than the `Source`: a navigation destination needs something
    /// `Hashable`, and a source carries a connection state that changes while the reader is
    /// inside it — which would pop the screen they are reading.
    @State var browsing: Source.ID?

    /// The term to hand a server's own search when one is opened from the library.
    @State var serverSearch = ""

    /// One search, put to the whole library at once.
    ///
    /// Held here rather than in the model because it is a question in progress rather than a
    /// fact about the library: leaving the search surface ends it, and the answers a server
    /// gave to a term nobody is typing any more are not worth keeping.
    @State var search = LibrarySearch()

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
        // `local-library`: a file brought in from elsewhere is copied into storage the app
        // owns, and a refusal names the file. Written, translated, and reachable from
        // nothing until the add menu that offers it was finally the one on screen.
        .importingPublications(into: model, isPresented: $isImporting)
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
                } else if let cachedAt = model.cachedAt {
                    // Last, because it is the quietest thing this strip has to say: a
                    // selection in progress or a folder that has gone missing both need the
                    // space more. `sources` asks for the indicator to be single and
                    // unobtrusive, and it leaves of its own accord — `cachedAt` goes back to
                    // `nil` the moment a walk finishes, at which point the shelf is current
                    // and a notice still claiming otherwise would be lying in the corner.
                    CachedNotice(refreshedAt: cachedAt)
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
    ///
    /// What the field is *over* changed with it. It used to be the shelf, narrowed — which
    /// made search a filter over what this device happens to hold, and left a reader's
    /// servers out of the only question they were being asked. Now a term puts the shelf
    /// away and puts up ``SearchResultsView``, which is one answer from every library the
    /// reader has.
    @ViewBuilder
    func searching(_ inner: some View) -> some View {
        if surface == .search {
            searchSurface(inner)
                .searchable(
                    text: searchBinding,
                    prompt: Text("library.search.prompt", bundle: .module)
                )
                // `library-browsing`: "when a user opens search, recent queries are
                // offered". Written and translated on both platforms; this modifier was
                // the missing half, so no iOS reader had ever seen one.
                .searchSuggestions { RecentSearchSuggestions(model: model) }
                // The one place the question is asked. Bound to the model's own term rather
                // than to a second piece of state, so a recent search chosen from the
                // suggestions runs exactly as if it had been typed.
                //
                // `initial: true` because the term outlives the session: `library-browsing`
                // keeps the query, so a reader who left mid-search and came back would
                // otherwise find the shelf narrowed by a term with no results under it and
                // nothing asked of any server.
                .onChange(of: model.query.search, initial: true) { _, term in
                    search.ask(term, in: model, credentials: credentials, pins: pins)
                }
                .onDisappear { search.clear() }
        } else {
            inner
        }
    }

    /// The shelf, or the answer to what was typed over it.
    @ViewBuilder
    private func searchSurface(_ inner: some View) -> some View {
        if search.isSearching {
            SearchResultsView(
                answers: search.answers,
                onOpenHeld: { id in
                    if let publication = model.publications.first(where: { $0.id == id }) {
                        open(publication)
                    }
                },
                // A row a server answered leads to that server, opened on the question
                // rather than at its front door. The reader is not told which server it was
                // until they are standing in it, which is the difference between routing a
                // tap and labelling a result.
                onFollow: { route in
                    serverSearch = search.answers.term
                    browsing = UUID(uuidString: route.sourceID)
                },
                onRetry: { id in
                    search.retry(id, in: model, credentials: credentials, pins: pins)
                }
            )
        } else {
            inner
        }
    }
}
