public import SwiftUI

public import Catalogue
internal import DesignSystem
internal import Formats
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
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        _browser = State(
            initialValue: CatalogueBrowser(
                title: title,
                url: url,
                credential: credential,
                pins: pins
            )
        )
        _queue = State(
            initialValue: DownloadQueue(
                pins: pins,
                store: DownloadStore(),
                credential: { _ in credential }
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

                switch state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StoryArcSpace.xl)
                case let .failed(message):
                    CatalogueFailure(message: message) {
                        Task { await browser.reload() }
                    }
                case .ready where shown.isEmpty && feed?.navigation.isEmpty != false:
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

    /// The formats besides the one a tap would take.
    ///
    /// `opds-catalog`: the app picks the best format and "lets the user choose another".
    /// Empty when there is nothing to choose between, so the menu does not offer a decision
    /// that has already been made.
    @ViewBuilder
    private func otherFormats(_ entry: OpdsEntry, offered: [OpdsAcquisition]) -> some View {
        if offered.count > 1 {
            ForEach(offered, id: \.href) { link in
                Button {
                    Task { await take(entry, using: link) }
                } label: {
                    Text("catalogue.acquire.other \(name(of: link))", bundle: .module)
                }
            }
        }
    }

    /// What tapping an entry does.
    ///
    /// `offline-downloads`: an already-downloaded publication is not re-fetched. It opens
    /// from disk, which also means it opens with no network at all.
    private func choose(_ entry: OpdsEntry) {
        if let file = queue.downloaded(entry) {
            Task { await open(entry, from: file) }
            return
        }
        guard let best = CatalogueAcquisition.best(of: entry) else { return }
        Task { await take(entry, using: best) }
    }

    /// Fetches one acquisition and hands what came back to the reader.
    private func take(_ entry: OpdsEntry, using link: OpdsAcquisition) async {
        guard let file = await queue.fetch(entry, using: link) else { return }
        await open(entry, from: file)
    }

    /// Opens a publication that is already on the device.
    private func open(_ entry: OpdsEntry, from file: URL) async {
        guard let publication = try? await PublicationIndexer.index(
            fileAt: file,
            catalogueSeries: entry.series
        ) else { return }
        onOpen(publication, file)
    }

    /// How an acquisition is named in the choose-a-format menu.
    private func name(of link: OpdsAcquisition) -> String {
        PublicationFormat(mediaType: link.mediaType)?.displayName ?? link.mediaType
    }

    /// A search the server answers, or one this page answers itself.
    private func runSearch() {
        switch browser.search(term) {
        case .server:
            searching = term
            filtered = nil
        case let .local(matches):
            filtered = matches
        case .cleared:
            filtered = nil
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
                NavigationLink {
                    CatalogueBrowserView(
                        title: section.title,
                        url: section.href,
                        credential: browser.credential,
                        pins: browser.pins,
                        onOpen: onOpen
                    )
                } label: {
                    CatalogueSectionRow(section: section)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(item: $searching) { term in
            if let url = browser.searchURL(for: term) {
                CatalogueBrowserView(
                    title: term,
                    url: url,
                    credential: browser.credential,
                    pins: browser.pins,
                    onOpen: onOpen
                )
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
                let offered = CatalogueAcquisition.readable(in: entry)
                Button {
                    choose(entry)
                } label: {
                    CatalogueEntryCell(
                        entry: entry,
                        credential: browser.credential,
                        client: browser.client,
                        isDownloaded: onDevice.contains(entry.id)
                    )
                }
                .buttonStyle(.plain)
                .disabled(offered.isEmpty)
                // `opds-catalog`: the app picks the best format and "lets the user choose
                // another". There is no detail screen yet, so the choice lives here —
                // shown only when there is one to make.
                .contextMenu {
                    if onDevice.contains(entry.id) {
                        Button(role: .destructive) {
                            queue.remove(entry.id)
                        } label: {
                            Text("downloads.remove", bundle: .module)
                        }
                    } else if let best = CatalogueAcquisition.best(of: entry) {
                        // `offline-downloads`: "the app SHALL let a user download any
                        // publication from a remote source for offline reading". Tapping
                        // opens it, which downloads it as a side effect; a reader packing
                        // for a flight wants the download without the reading.
                        Button {
                            queue.enqueue(entry, using: best)
                        } label: {
                            Text("catalogue.acquire.download", bundle: .module)
                        }
                    }

                    otherFormats(entry, offered: offered)
                }
                .task {
                    // The next page arrives because the reader scrolled, not because they
                    // pressed anything. Skipped while a local filter is showing: the filter
                    // is over what is loaded, and loading more would change it underneath.
                    if filtered == nil { await browser.loadMore(after: entry) }
                }
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

/// A section, with its count where the feed gave one.
struct CatalogueSectionRow: View {
    @Environment(\.theme) private var theme

    let section: OpdsSection

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(section.title)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)

                if let count = section.count {
                    Text("catalogue.section.count \(count)", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(StoryArcSpace.md)
        .frame(minHeight: StoryArcSpace.xxl + StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}
