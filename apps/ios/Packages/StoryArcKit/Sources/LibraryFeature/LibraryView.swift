public import SwiftUI

internal import DesignSystem
public import Persistence
internal import Catalogue
internal import UniformTypeIdentifiers
public import StoryArcCore

/// The library.
///
/// Three states, in the order a user meets them: nothing added, a scan running,
/// and a grid of covers, with search, filtering and sorting over the last of
/// them.
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

    /// How wide the window is, and nothing about what device it belongs to.
    ///
    /// `native-experience` wants the layout to follow the window through Split View,
    /// Slide Over, a rotation and — on the Android side of the mirror — a fold. All of
    /// those are one event: the width changed. Measured rather than taken from
    /// `horizontalSizeClass`, which is coarse where the spec asks for a layout that
    /// "reflows continuously", and which has no counterpart Android could agree with.
    @State var width: CGFloat = 0

    /// Which sidebar row is showing, in a window wide enough to have one. Optional
    /// because `List` on iOS takes an optional selection: nothing selected is a state
    /// the platform allows, and the library is what the detail column then shows.
    @State var sidebar: SidebarDestination? = .library
    /// Owned by the app layer, not by this view.
    ///
    /// The app is what knows the reader was just dismissed, and a `.task` on this
    /// view does not fire again when a full-screen cover goes away — so the
    /// progress bars under the covers never updated. Whoever can observe the
    /// return has to be the one holding the model.
    let model: LibraryModel

    let onOpen: (Publication, URL) -> Void
    let progress: ProgressStore?
    let onOpenSettings: () -> Void
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
        progress: ProgressStore? = nil,
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in },
        /// How the app layer reaches Settings.
        ///
        /// The library does not know what a settings screen is, for the same reason it
        /// does not know what a reader is: a feature target never depends on another
        /// feature target. It reports that the reader asked.
        onOpenSettings: @escaping () -> Void = {},
        /// How often the app layer has asked for the shelf itself.
        ///
        /// `native-experience`'s home-screen menu offers the library, and that entry
        /// promises the shelf rather than wherever the reader last was — a reader who left
        /// the app inside a catalogue would otherwise be handed the catalogue back. Where
        /// this view has navigated to is `@State`, which nothing outside can reach, so the
        /// app layer changes a number and the view answers by unwinding itself.
        showLibrary: Int = 0
    ) {
        self.model = model
        self.progress = progress
        self.onOpenSettings = onOpenSettings
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

    /// Opens a catalogue.
    func open(_ source: Source) {
        browsing = source.id
    }

    /// Where a publication lives, handed to the app layer.
    func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }

    /// Every catalogue, server and share the reader has added, in registry order.
    ///
    /// All three together: each is a place to browse rather than a shelf of local
    /// publications, and a reader with one of each should not have to learn three ways
    /// in. The sidebar lists exactly this set, for exactly this reason.
    var catalogues: [Source] {
        model.registry.sources.filter { $0.kind.isBrowsable }
    }

    /// Whether this window has room for the platform's split navigation.
    /// Not `private`: the toolbar is the other half of this view and lives in
    /// `LibraryToolbar.swift`, and Swift's `private` is file-scoped — so the split that
    /// keeps this file under the line cap is what widens these.
    var windowClass: StoryArcWindowClass { .of(width: width) }

    /// What the reader has picked, when they are picking.
    ///
    /// Held here rather than in either layout: a reader may switch between the grid and the
    /// list mid-selection and should not lose what they picked, and the sidebar layout is
    /// another switch of exactly that kind.
    @State var selection = LibrarySelection()

    public var body: some View {
        Group {
            if windowClass.showsSidebar { split } else { stacked }
        }
        // The one input to the layout, and it is the window's own. Measured on the
        // outermost view so it is the window being measured and not a column of it,
        // which is what keeps a Split View drag, a rotation and — on the mirror side —
        // an Android fold the same event.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The shelf, asked for by name. Both layouts, because a wide window can be sitting
        // in a source and a narrow one can have pushed into it.
        .onChange(of: showLibrary) { _, _ in
            browsing = nil
            sidebar = .library
        }
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

    /// The narrow window: one column, and everything else behind chrome.
    var stacked: some View {
        NavigationStack {
            libraryColumn
                // Above the grid rather than inside it: a catalogue holds nothing that is
                // on the device, and mixing the two would make "what can I read on the
                // train" unanswerable. A bar rather than a plain inset, because
                // `safeAreaBar` is what tells the scroll beneath it that there is chrome
                // here — which is the scroll edge effect `native-experience` asks for at
                // a content boundary. An inset only reserved space, and the covers slid
                // under a hard edge.
                .safeAreaBar(edge: .top, spacing: 0) {
                    if !catalogues.isEmpty { CatalogueStrip(sources: catalogues) { open($0) } }
                }
                .navigationDestination(item: $browsing) { id in
                    if let source = model.registry[id] { browser(for: source) }
                }
        }
    }

    /// The wide window: the platform's own split navigation.
    ///
    /// `native-experience`: a large screen "uses a multi-column layout with a persistent
    /// sidebar, not a stretched phone layout". `NavigationSplitView` is that layout, and
    /// brings the column widths, the collapse behaviour and the toggle with it.
    var split: some View {
        NavigationSplitView {
            LibrarySidebar(
                sources: model.registry.sources,
                selection: $sidebar,
                onOpenSettings: onOpenSettings
            )
        } detail: {
            NavigationStack {
                switch sidebar ?? .library {
                case .library:
                    libraryColumn
                case let .source(id):
                    if let source = model.registry[id] { browser(for: source) }
                case .shelves:
                    ShelvesView(model: model, onOpen: onOpen)
                }
            }
        }
    }

    /// The way in to one source, wherever it is being shown from.
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
    ///
    /// One property, not one per layout: it is the same screen either way, and only the
    /// column it is handed to changes.
    var libraryColumn: some View {
        content
            .navigationTitle(Text("library.title", bundle: .module))
            // `library-browsing`: results update as the user types, debounced, with
            // no submit action. SwiftUI's own field already debounces per keystroke
            // through the binding, and the arrange is a sort of what is in memory.
            .searchable(
                text: searchBinding,
                prompt: Text("library.search.prompt", bundle: .module)
            )
            // `library-browsing`: "when a user opens search, recent queries are offered".
            // The list, its rules and its storage were on both platforms; this modifier
            // was the missing half, so no iOS reader had ever seen one.
            .searchSuggestions { RecentSearchSuggestions(model: model) }
            // Reloaded on every appearance, which is what makes the bar under a
            // cover reflect the page the reader just reached.
            .task {
                model.restoreFolders()
                await model.refreshProgress()
                await model.probeNetworkSources(credentials: credentials, pins: pins)
                // And keeps asking while anything is away, per `sources`' backoff. Written,
                // documented and called by nothing until now, so an unreachable source was
                // only ever re-probed when this view next appeared — a reader whose Wi-Fi
                // came back while they were looking at the shelf watched it stay grey.
                //
                // After the probe rather than beside it: the loop stops as soon as nothing
                // is unreachable, so started before the first answer it would stop before
                // there was one. Cancellation is this modifier's, which is exactly when
                // nobody is looking at the answer — and returning to the foreground starts
                // it again, which is the requirement's other half.
                await model.retryUnreachableSources(credentials: credentials, pins: pins)
            }
            // Written, documented and applied to nothing until now, so `local-library`'s
            // "reconciles ... after files changed" was reachable only from the watcher's
            // own callback — and a provider notifies nobody while the app is away. Android
            // does the same on `ON_RESUME`.
            .watchingFolders(of: model)
            // `sources` names pull-to-refresh: a refresh "re-fetches the catalogue in the
            // background" and updates the view "incrementally rather than clearing it". iOS
            // had no reader-initiated refresh at all; Android has a toolbar button.
            .refreshable {
                await model.probeNetworkSources(credentials: credentials, pins: pins)
                await model.rescan()
            }
            .toolbar { toolbarItems }
            // A bar, so the notice floats on glass and the shelf fades out beneath it
            // rather than being clipped by it.
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

}
