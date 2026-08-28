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
    @Environment(\.theme) private var theme
    @State private var isPickingFolder = false
    @State private var isAddingCatalogue = false
    @State private var isAddingKavita = false
    @State private var isAddingShare = false

    /// The catalogue being browsed, by identifier.
    ///
    /// The identifier rather than the `Source`: a navigation destination needs something
    /// `Hashable`, and a source carries a connection state that changes while the reader is
    /// inside it — which would pop the screen they are reading.
    @State private var browsing: Source.ID?
    /// Owned by the app layer, not by this view.
    ///
    /// The app is what knows the reader was just dismissed, and a `.task` on this
    /// view does not fire again when a full-screen cover goes away — so the
    /// progress bars under the covers never updated. Whoever can observe the
    /// return has to be the one holding the model.
    private let model: LibraryModel

    private let onOpen: (Publication, URL) -> Void
    private let progress: ProgressStore?
    private let onOpenSettings: () -> Void

    /// One pin set for the whole app, loaded once.
    ///
    /// Shared between adding a catalogue and browsing one on purpose: a certificate the
    /// reader accepted while adding a server has to still be accepted when its covers load.
    @State private var pins: CertificatePins
    private let pinStore = CertificatePinStore()
    private let credentials = CredentialStore()
    private let kavitaProgress = KavitaProgressStore()
    @State private var smb = SmbConnection(credentials: CredentialStore())

    /// Held by the view rather than made per presentation, so a reader who dismisses the
    /// sheet mid-sign-in and reopens it finds what they typed still there.
    @State private var catalogue: CatalogueConnection
    @State private var kavita: KavitaConnection

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
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.progress = progress
        self.onOpenSettings = onOpenSettings
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
            initialValue: KavitaConnection(pins: loaded, credentials: CredentialStore())
        )
    }

    /// The search text, written straight through to the query.
    ///
    /// `@Bindable` on the model would be the idiomatic shape, and it cannot be
    /// used here: the model is a `let` owned by the app layer, not state this view
    /// creates. A binding does the same job without pretending otherwise.
    private var searchBinding: Binding<String> {
        Binding(get: { model.query.search }, set: { model.query.search = $0 })
    }

    /// Opens a catalogue.
    private func open(_ source: Source) {
        browsing = source.id
    }

    /// Where a publication lives, handed to the app layer.
    private func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }

    /// Every server the reader has added, in registry order.
    ///
    /// Catalogues and Kavita servers together: both are places to browse rather than
    /// shelves of local publications, and a reader with one of each should not have to
    /// learn two ways in.
    private var catalogues: [Source] {
        // Catalogues, servers and shares together: all three are places to browse rather
        // than shelves of local publications, and a reader with one of each should not have
        // to learn three ways in.
        model.registry.sources.filter {
            $0.kind == .opdsCatalog || $0.kind == .kavitaServer || $0.kind == .networkShare
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !model.visible.isEmpty {
                    if model.layout == .grid {
                        CoverGrid(
                            publications: model.visible,
                            // Hidden while a search or filter is running: the row
                            // is a shortcut to what you were reading, and showing
                            // publications the query excluded reads as a bug.
                            continueReading: model.query.isNarrowed ? [] : model.continueReading,
                            model: model,
                            onOpen: open
                        )
                    } else {
                        CoverList(publications: model.visible, model: model, onOpen: open)
                    }
                } else if !model.publications.isEmpty {
                    // A library that is not empty but looks it. `library-browsing`
                    // forbids showing that silently: say what is narrowing it and
                    // offer one action to undo.
                    NarrowedToNothing(query: model.query) {
                        model.clearFilters()
                        model.query.search = ""
                    }
                } else if case .scanning = model.scanState {
                    ScanningView(state: model.scanState)
                } else if model.registry.sources.isEmpty {
                    EmptyLibraryView(
                        addFolder: { isPickingFolder = true },
                        addCatalogue: { isAddingCatalogue = true },
                        addKavita: { isAddingKavita = true }
                    )
                } else {
                    SourceList(
                        sources: model.registry.sources,
                        itemCount: { model.itemCount(of: $0) },
                        onRemove: { model.remove($0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.surfaceCanvas)
            // Above the grid rather than inside it. A catalogue is not a shelf of local
            // publications — nothing in it is on the device yet — and mixing the two would
            // make "what can I read on the train" unanswerable.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !catalogues.isEmpty { CatalogueStrip(sources: catalogues) { open($0) } }
            }
            .navigationDestination(item: $browsing) { id in
                if let source = model.registry[id] {
                    // Two kinds of server, two browsers, one door out: whatever is opened
                    // goes to the same reader a local publication does.
                    if let page = CataloguePage(source: source, credentials: credentials) {
                        CatalogueBrowserView(
                            title: page.title,
                            url: page.url,
                            credential: page.credential,
                            pins: pins,
                            onOpen: onOpen
                        )
                    } else if let page = SmbPage(source: source, credentials: credentials) {
                        SmbBrowserView(
                            title: page.title,
                            address: page.address,
                            path: page.address.path,
                            onOpen: onOpen
                        )
                    } else if let page = KavitaPage(source: source, credentials: credentials) {
                        KavitaBrowserView(
                            title: page.title,
                            address: page.address,
                            sourceId: page.id,
                            store: kavitaProgress,
                            lists: model.serverLists,
                            onOpen: onOpen
                        )
                    } else {
                        // Neither page could be built, which means the secret this source
                        // needs is not in the keychain any more. Saying so beats the blank
                        // screen this used to push -- a screen with nothing on it and no way
                        // to tell whether the server was slow or the app was broken.
                        UnreachableSource(name: source.displayName)
                    }
                }
            }
            .navigationTitle(Text("library.title", bundle: .module))
            // `library-browsing`: results update as the user types, debounced, with
            // no submit action. SwiftUI's own field already debounces per keystroke
            // through the binding, and the arrange is a sort of what is in memory.
            .searchable(
                text: searchBinding,
                prompt: Text("library.search.prompt", bundle: .module)
            )
            // Reloaded on every appearance, which is what makes the bar under a
            // cover reflect the page the reader just reached.
            .task {
                model.restoreFolders()
                await model.refreshProgress()
                await model.probeNetworkSources(credentials: credentials, pins: pins)
            }
            .toolbar {
                if !model.publications.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        LayoutToggle(model: model)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        SortMenu(model: model)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        FilterMenu(model: model)
                    }
                }
                // A menu rather than a second button. There are two ways to add a
                // source now and there will be four; a toolbar with one button per kind
                // would crowd out the controls a reader uses every day.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPickingFolder = true
                        } label: {
                            Label {
                                Text("library.addFolder", bundle: .module)
                            } icon: {
                                Image(systemName: "folder.badge.plus")
                            }
                        }
                        Button {
                            isAddingCatalogue = true
                        } label: {
                            Label {
                                Text("catalogue.title", bundle: .module)
                            } icon: {
                                Image(systemName: "dot.radiowaves.up.forward")
                            }
                        }
                        Button {
                            isAddingKavita = true
                        } label: {
                            Label {
                                Text("kavita.title", bundle: .module)
                            } icon: {
                                Image(systemName: "externaldrive.connected.to.line.below")
                            }
                        }
                        Button {
                            isAddingShare = true
                        } label: {
                            Label {
                                Text("smb.title", bundle: .module)
                            } icon: {
                                Image(systemName: "externaldrive.badge.wifi")
                            }
                        }
                    } label: {
                        Label {
                            Text("library.addSource", bundle: .module)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
                // Last, and always present. A reader with an empty library still needs
                // to reach About, and `settings-and-about` puts the licences there.
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ShelvesView(model: model, onOpen: onOpen)
                    } label: {
                        Label {
                            Text("shelves.title", bundle: .module)
                        } icon: {
                            Image(systemName: "square.stack")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onOpenSettings) {
                        Label {
                            Text("library.settings", bundle: .module)
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let missing = model.unavailableFolders.first {
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
}

/// A folder that was remembered and can no longer be read.
///
/// `local-library`: "the source is marked `unauthorized` with a plain-language
/// explanation naming the folder", and "a single action re-picks the folder,
/// preserving reading progress for everything inside it". Progress survives
/// because ADR-0006 keys it on the publication, not on the folder.
struct UnavailableFolderNotice: View {
    @Environment(\.theme) private var theme

    let name: String
    let repick: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.sm) {
            Text("library.folderUnavailable \(name)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            Spacer(minLength: 0)

            Button(action: repick) {
                Text("library.repick", bundle: .module)
                    .textRole(.footnote)
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .storyArcGlass(in: Rectangle())
    }
}
