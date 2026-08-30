import SwiftUI

internal import Formats
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Searching one Kavita server, and what the search does when the server does not answer.
///
/// **`kavita-server`'s two search scenarios, and the reason both were absent.** The clients
/// have had a `search` method on both platforms since the capability was built, tested on
/// both, and called by nothing: there was no field on the libraries screen, the series grid
/// or the chapter list. So the server-side scenario had no way in, and its unreachable
/// counterpart had nothing to degrade.
///
/// One finder, carried down all three levels rather than one per screen, which is what makes
/// the iOS field behave like Android's — a search on this server, not a search of whichever
/// list happens to be on screen.
///
/// The degradation follows the pattern `opds-catalog` already set in ``CatalogueBrowser``:
/// ask the server when it can be asked, filter what is held when it cannot, and *say which
/// one happened*. What is held here is the cards beside downloads — see ``KavitaCardStore``
/// for why that is the only Kavita answer written to disk.
@MainActor
@Observable
final class KavitaFinder {
    /// What the reader typed. Bound to the search field.
    var term = ""

    /// What the last run found.
    private(set) var hits: [KavitaHit] = []

    /// Whether those hits came from the device rather than the server.
    ///
    /// The reader is told, per the scenario: results "limited to cached content" is a
    /// different answer from no results, and a reader who is not told will read the second.
    private(set) var isCached = false

    /// Whether a run has finished for the term now in the field.
    private(set) var hasAnswered = false

    init() {}

    /// Whether the results should be on screen instead of the level behind them.
    var isShowing: Bool { KavitaFind.term(term) != nil }

    /// Asks the server, and falls back to the cache when it will not answer.
    func run(_ client: KavitaClient, sourceId: String) async {
        guard let wanted = KavitaFind.term(term) else {
            hits = []
            isCached = false
            hasAnswered = false
            return
        }
        hasAnswered = false
        if let answered = try? await client.find(wanted) {
            hits = answered
            isCached = false
        } else {
            hits = KavitaFind.inCache(wanted, KavitaCardStore().all(from: sourceId))
            isCached = true
        }
        hasAnswered = true
    }

    /// Empties the field and everything that came of it.
    func clear() {
        term = ""
        hits = []
        isCached = false
        hasAnswered = false
    }
}

extension View {
    /// The search field every level of a Kavita server carries.
    ///
    /// A modifier rather than three copies: iOS pushes a view per level and each carries its
    /// own toolbar, so the alternative to this is the same twenty lines three times, drifting
    /// apart the first time one of them is corrected.
    func kavitaSearchable(_ finder: KavitaFinder, run: @escaping () async -> Void) -> some View {
        searchable(text: Binding(
            get: { finder.term },
            set: { finder.term = $0 }
        ), prompt: Text("kavita.search.prompt", bundle: .module))
        .onSubmit(of: .search) { Task { await run() } }
        .onChange(of: finder.term) { _, now in
            if now.isEmpty { finder.clear() }
        }
    }
}

/// What a search of a Kavita server found, under the spec's own five headings.
struct KavitaHits: View {
    @Environment(\.theme) private var theme

    let finder: KavitaFinder
    let client: KavitaClient
    let sourceId: String
    let store: KavitaProgressStore
    var progress: ProgressStore?
    var lists: [ServerShelf] = []
    let onOpen: (Publication, URL) -> Void

    /// The series a tapped row resolved to, which is what gets pushed.
    @State private var opening: KavitaSeries?

    var body: some View {
        List {
            if finder.isCached {
                // The scenario's own words: the search "states that results are limited to
                // cached content". Saying so is the whole difference between a degraded
                // answer and a wrong one.
                Text("kavita.search.cached", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if finder.hasAnswered, finder.hits.isEmpty {
                Text("kavita.search.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            ForEach(KavitaFind.grouped(finder.hits), id: \.kind) { group in
                Section {
                    ForEach(group.hits) { hit in
                        row(hit)
                    }
                } header: {
                    Text(Self.heading(group.kind), bundle: .module)
                }
            }
        }
        .navigationDestination(item: $opening) { series in
            KavitaChapterList(
                client: client,
                series: series,
                sourceId: sourceId,
                store: store,
                progress: progress,
                lists: lists,
                onOpen: onOpen
            )
        }
    }

    @ViewBuilder
    private func row(_ hit: KavitaHit) -> some View {
        if hit.publicationId != nil || hit.isOpenable {
            Button {
                Task { await open(hit) }
            } label: {
                Text(hit.title)
                    .foregroundStyle(theme.palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else {
            // A person and a subject are names the server matched, not places. A row that
            // looked tappable and did nothing would be worse than one that plainly is not.
            Text(hit.title)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// Opens what a row names: the download when the row came from the cache, the series on
    /// the server when it came from the server.
    ///
    /// The series is asked for by identity rather than built from the row. Kavita keys
    /// progress by library *and* series and a search result does not always carry the
    /// library, so a series built from the row alone would report reading against library
    /// zero for as long as the reader stayed in it.
    private func open(_ hit: KavitaHit) async {
        if let publicationId = hit.publicationId {
            await openKept(publicationId)
            return
        }
        opening = try? await client.seriesDetail(hit.seriesId)
    }

    /// Opens a download this device already holds.
    private func openKept(_ publicationId: String) async {
        let downloads = DownloadStore()
        guard let download = downloads.library()[publicationId] else { return }
        let file = downloads.location(of: download)
        guard FileManager.default.fileExists(atPath: file.path()),
              let publication = try? await PublicationIndexer.index(fileAt: file)
        else { return }
        onOpen(publication, file)
    }

    private static func heading(_ kind: KavitaHit.Kind) -> LocalizedStringKey {
        switch kind {
        case .series: "kavita.search.series"
        case .chapter: "kavita.search.chapters"
        case .person: "kavita.search.people"
        case .subject: "kavita.search.subjects"
        }
    }
}
