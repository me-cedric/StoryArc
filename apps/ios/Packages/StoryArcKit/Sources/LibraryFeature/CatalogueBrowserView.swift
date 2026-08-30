public import SwiftUI

public import Catalogue
internal import DesignSystem
public import Persistence
public import StoryArcCore

/// A page of a catalogue: its sections, then its publications.
///
/// Both on one screen, because a real feed carries both — Calibre-Web puts "Recently
/// added" beside its sections — and a screen that showed one and hid the other would make
/// half of every catalogue unreachable.
public struct CatalogueBrowserView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.theme) private var theme

    /// Created here, once, from the values that describe the page.
    ///
    /// Owned rather than handed in. A destination closure is re-evaluated whenever the
    /// screen behind it redraws, so a browser built inside one is a *new* browser each
    /// time — the page fetched twice and displayed a third instance that had never
    /// fetched at all, which showed as a permanently blank catalogue.
    @State private var browser: CatalogueBrowser

    /// Where a fetched publication goes — the same door the library uses.
    private let onOpen: (Publication, URL) -> Void

    /// What is downloading, and what is already here.
    @State private var queue: DownloadQueue

    /// The term as typed, and the result of the last search that was not the server's.
    @State private var term = ""
    @State private var filtered: [OpdsEntry]?

    public init(
        title: String,
        url: URL,
        credential: OpdsCredential?,
        pins: CertificatePins,
        /// The configured source's origin. Nil at the top of a catalogue, where this
        /// screen's own address is it; carried down explicitly from every screen below,
        /// because their addresses come out of a feed.
        origin: OpdsOrigin? = nil,
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        let home = origin ?? OpdsOrigin(url: url)
        _browser = State(
            initialValue: CatalogueBrowser(
                title: title,
                url: url,
                credential: credential,
                pins: pins,
                origin: home
            )
        )
        _queue = State(
            initialValue: DownloadQueue(
                pins: pins,
                store: DownloadStore(),
                credential: { _ in credential },
                origin: home
            )
        )
        self.onOpen = onOpen
    }

    public var body: some View {
        // Read here, in the body, and passed down.
        //
        // A `LazyVStack` evaluates its content closure when a row is about to appear, which
        // is outside the observation scope of this body. An `@Observable` property read in
        // there registers no dependency, so the first evaluation is the only one — the page
        // stayed on its initial empty state and never showed what it had fetched.
        let state = browser.state
        let feed = browser.feed
        let shown = filtered ?? browser.entries
        let onDevice = queue.onDevice
        let active = queue.library.pending

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                if let feed, !feed.navigation.isEmpty {
                    sections(feed.navigation)
                }

                if filtered != nil {
                    // `opds-catalog`: a catalogue with no search "falls back to filtering
                    // the cached catalogue, and says so". This is the saying so.
                    Text("catalogue.search.local", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }

                if !shown.isEmpty {
                    publications(shown, onDevice: onDevice)
                }

                // After the feed's own publications, because a group is a named part of the
                // page and the page's own run of covers is the unnamed rest of it. Hidden
                // while a local filter is showing: the filter is over a flat list of
                // matches, and a match has left the group it was found in.
                if let feed, filtered == nil, !feed.groups.isEmpty {
                    groups(feed.groups, onDevice: onDevice)
                }

                switch state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StoryArcSpace.xl)
                case let .failed(message):
                    CatalogueFailure(message: message) {
                        Task { await browser.reload() }
                    }
                case .ready where shown.isEmpty && feed?.isEmpty != false:
                    Text("catalogue.empty", bundle: .module)
                        .textRole(.subheadline)
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StoryArcSpace.xl)
                case .ready, .idle:
                    EmptyView()
                }
            }
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
        // On the page itself, not on the run of sections: a feed can be all publications or
        // all groups and have no sections at all, and a destination declared inside one that
        // is never rendered is a search the server answers into nowhere.
        .navigationDestination(item: $searching) { term in
            if let url = browser.searchURL(for: term) {
                CatalogueBrowserView(
                    title: term,
                    url: url,
                    credential: browser.credential,
                    pins: browser.pins,
                    origin: browser.origin,
                    onOpen: onOpen
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let first = active.first {
                DownloadBanner(
                    download: first,
                    others: active.count - 1,
                    onCancel: { queue.cancel(first.id) },
                    onResume: { queue.resume(first.id) }
                )
            }
        }
        .navigationTitle(browser.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $term, prompt: Text("catalogue.search.prompt", bundle: .module))
        .onSubmit(of: .search) { runSearch() }
        .onChange(of: term) { _, now in
            if now.isEmpty { filtered = nil }
        }
        .toolbar {
            if let facets = feed?.facets, !facets.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    facetMenu(facets)
                }
            }
        }
        .task { await browser.load() }
        // Coming back is when a lost transfer becomes visible: the system's list of tasks
        // is the only thing that knows whether a download the queue calls running is one
        // anybody is still carrying.
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            Task { await queue.reclaim() }
        }
    }

    /// A search the server answers, or one this page answers itself.
    private func runSearch() {
        // Asked rather than read again when the answer arrives: resolving an OpenSearch
        // description document is a request, and the reader can have typed on since.
        let asked = term
        Task {
            switch await browser.search(asked) {
            case .server:
                searching = asked
                filtered = nil
            case let .local(matches):
                filtered = matches
            case .cleared:
                filtered = nil
            }
        }
    }

    /// A server-answered search opens as its own page, like entering a section.
    ///
    /// Held as a term rather than the page itself: `navigationDestination(item:)` needs
    /// something `Hashable`, and a browser is a reference type whose identity would change
    /// on every recomposition.
    @State private var searching: String?

    @ViewBuilder
    private func sections(_ list: [OpdsSection]) -> some View {
        VStack(spacing: StoryArcSpace.sm) {
            ForEach(list) { section in
                CatalogueSectionLink(section: section, browser: browser, onOpen: onOpen)
            }
        }
    }

    @ViewBuilder
    private func publications(_ shown: [OpdsEntry], onDevice: Set<String>) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: StoryArcSpace.huge * 2), spacing: StoryArcSpace.md)],
            spacing: StoryArcSpace.lg
        ) {
            ForEach(shown) { entry in
                CatalogueEntryLink(
                    entry: entry,
                    browser: browser,
                    queue: queue,
                    isDownloaded: onDevice.contains(entry.id),
                    onOpen: onOpen
                )
                .task {
                    // The next page arrives because the reader scrolled, not because they
                    // pressed anything. Skipped while a local filter is showing: the filter
                    // is over what is loaded, and loading more would change it underneath.
                    if filtered == nil { await browser.loadMore(after: entry) }
                }
            }
        }
    }

    /// The named runs of an OPDS 2.0 feed, each with its own title and its own row.
    ///
    /// Keyed by position rather than by title: nothing in the standard makes a group's name
    /// unique, and two groups sharing one would collapse into a single row.
    @ViewBuilder
    private func groups(_ list: [OpdsGroup], onDevice: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, group in
                CatalogueGroupSection(
                    group: group,
                    browser: browser,
                    queue: queue,
                    onDevice: onDevice,
                    onOpen: onOpen
                )
            }
        }
    }

    @ViewBuilder
    private func facetMenu(_ facets: [OpdsFacet]) -> some View {
        Menu {
            let grouped = Dictionary(grouping: facets, by: \.group).sorted { $0.key < $1.key }
            ForEach(grouped, id: \.key) { group, members in
                Section(group) {
                    ForEach(members) { facet in
                        NavigationLink {
                            CatalogueBrowserView(
                                title: facet.title,
                                url: facet.href,
                                credential: browser.credential,
                                pins: browser.pins,
                                origin: browser.origin,
                                onOpen: onOpen
                            )
                        } label: {
                            if facet.isActive {
                                Label(facet.title, systemImage: "checkmark")
                            } else {
                                Text(facet.title)
                            }
                        }
                    }
                }
            }
        } label: {
            Label {
                Text("catalogue.facets", bundle: .module)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease")
            }
        }
    }
}
