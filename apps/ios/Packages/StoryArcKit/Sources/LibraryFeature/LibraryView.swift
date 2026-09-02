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

    /// The download group of the filter, which is a facet rather than an axis.
    ///
    /// Beside ``availability`` and not inside it: ``DownloadFilter`` sets out why the two
    /// are different questions. Stored the same way, and for the same reason — the query is
    /// what both platforms encode, and `library-browsing` asks that a filter still be
    /// applied when the reader comes back.
    @AppStorage(DownloadFilter.storageKey)
    var downloads: DownloadFilter = .either

    /// What the search screen is narrowed to.
    ///
    /// The same type as ``availability`` under a **different key**, which is the whole point:
    /// they are the same question asked about two screens. A shared key would have narrowing a
    /// search on a train silently narrow the shelf the reader goes back to — a filter they
    /// never set, on a destination `navigation-shell` promises to return "with its scroll
    /// position and filters intact".
    ///
    /// `library-browsing` asks this choice to persist "until changed" in its own right, which
    /// is why it is stored rather than held in `@State`.
    @AppStorage(LibraryAvailability.searchScopeKey)
    var searchScope: LibraryAvailability = .everywhere

    /// Whether the file picker is open for an import.
    ///
    /// The empty states offer "Open a comic" as their primary action — two taps to a
    /// readable page with nothing configured — and until this existed the library had no
    /// way to present the picker that does it. Home had one; the shelf did not, so the same
    /// offer could not be made on the destination a reader lands on when the library is
    /// what is empty.

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

    // `open(_:)` used to be here, and nothing on this screen calls it any more: every cover
    // and every search result leads to the publication's page, and the page is what reaches
    // the reader. `onOpen` is still the library's one way out to a reader — it is handed to
    // `publicationPages(in:onOpen:)` below and to the source browsers, which open a server's
    // or a share's file directly because it is not a publication the library holds yet.

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
        VStack(spacing: 0) {
            // Above the shelf and inside the layout, not floating over it. The notice this
            // replaced was a glass capsule in the `safeAreaBar` below, which put a sentence
            // over whatever cover happened to scroll under it — see ``SkippedNotice``.
            //
            // The shelf only. The toast appeared on Library, Search and Downloads alike,
            // which is three surfaces reporting one folder walk; this belongs to the one
            // that walked it.
            if surface == .shelf {
                SkippedNotice(skipped: model.skipped) { model.dismissSkipped() }
            }
            shelf
        }
    }

    private var shelf: some View {
        searching(content)
            // Once, at the root of this stack, for every cover on all three of its surfaces:
            // the shelf, the on-device set, and the results of a search. The page opens
            // inside the destination the reader was already on, so going back lands on the
            // shelf with its scroll position, its filters and its selection intact — which is
            // what `publication-detail` asks for and what a sheet or a separate stack would
            // have cost.
            .publicationPages(in: model, onOpen: onOpen)
            // The title becomes the selection state while one is running, which is the
            // first of the three things Photos, Files and Mail all do and StoryApp did
            // none of: with the count in the navigation bar, no bottom bar has to carry a
            // label, and the bottom bar was full-bleed with a left-aligned label precisely
            // because it did. Inline for the duration, so the count sits on one line
            // beside *Done* rather than under a large title that has nothing to say.
            .navigationTitle(selection.isActive ? selectionTitle : title)
            // `#if os(iOS)` around both of the modifiers below, and around nothing else:
            // `swift test` builds this package for the host, and a navigation bar's display
            // mode and a tab bar are both things macOS does not have. Same guard, and same
            // reason, as `ReaderSystemChrome` and the pager's style.
            #if os(iOS)
            // Inline for the duration, so the count sits on one line beside *Done* rather
            // than under a large title that has nothing left to say.
            .navigationBarTitleDisplayMode(selection.isActive ? .inline : .automatic)
            // **And the tab bar goes down for exactly as long as the selection is up.**
            // This is the line that fixes what the owner reported: the actions used to be
            // drawn in a bar stacked *above* the rounded glass tab bar, so the foot of the
            // screen showed two bars of two shapes at once. While a reader is picking, the
            // bottom of the screen is not for going somewhere else — it is for acting on
            // what was picked — which is why every Apple app with a selection takes its own
            // tab bar down and puts it back on the way out. `BulkSelectionChromeTests`
            // pins it, and the way out stays in the navigation bar throughout so nothing
            // is stranded by it.
            .toolbar(selection.isActive ? .hidden : .automatic, for: .tabBar)
            #endif
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

    /// What the navigation bar says instead, while a selection is running.
    ///
    /// The count, stated in the one place a reader is already looking for the name of what
    /// they are on. It is a plural in all four languages — `library.selected %lld` carries
    /// the variations — and it is stated at nought as well: the mode can be entered without
    /// picking anything, and a title that only appeared on the first pick would leave the
    /// navigation bar naming a shelf the reader has stopped browsing.
    var selectionTitle: Text {
        Text("library.selected \(selection.count)", bundle: .module)
    }
}
