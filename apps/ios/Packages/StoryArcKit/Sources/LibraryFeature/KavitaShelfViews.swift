import SwiftUI

internal import DesignSystem
internal import Formats
import Kavita
import Persistence
import StoryArcCore

/// One of a server's own shelves.
///
/// A collection and a reading list differ in kind — one groups series with no order, the
/// other is an ordered run of chapters — so the flag chooses the screen rather than one
/// screen guessing from what it finds.
public struct ServerShelf: Identifiable, Sendable {
    public let server: KavitaPage
    public let id: Int
    public let title: String
    public let isList: Bool

    /// Every Kavita server's shelves, asked for once.
    static func all(
        in registry: SourceRegistry,
        credentials: CredentialStore?
    ) async -> [ServerShelf] {
        await fetch(in: registry, credentials: credentials).shelves
    }

    /// The shelves, and the servers that could be asked for them at all.
    ///
    /// Both come out of the same round of requests because they are the same question asked
    /// once. Keeping them apart matters: a server with no reading lists yet still *supports*
    /// them, and one that did not answer does not — a distinction an empty array cannot make,
    /// and the one `collections-and-reading-lists` needs before it offers to copy a list.
    static func fetch(
        in registry: SourceRegistry,
        credentials: CredentialStore?
    ) async -> ServerShelves {
        var found: [ServerShelf] = []
        var listCapable: [KavitaPage] = []
        for source in registry.sources {
            guard let page = KavitaPage(source: source, credentials: credentials) else { continue }
            let client = KavitaClient(address: page.address)
            let collections = (try? await client.collections()) ?? []
            found += collections.map {
                ServerShelf(server: page, id: $0.id, title: $0.title, isList: false)
            }
            // Answered rather than non-empty: a server that has no lists yet is exactly the
            // one a reader is most likely to want to copy their first list onto.
            guard let lists = try? await client.readingLists() else { continue }
            listCapable.append(page)
            found += lists.map {
                ServerShelf(server: page, id: $0.id, title: $0.title, isList: true)
            }
        }
        return ServerShelves(shelves: found, listCapable: listCapable)
    }
}

/// What one round of asking every server produced.
struct ServerShelves: Sendable {
    let shelves: [ServerShelf]

    /// The servers that answered when asked for their reading lists — reachable, and able to
    /// hold one. A server that did not answer is simply not offered.
    let listCapable: [KavitaPage]
}

/// The series in one of a server's collections.
///
/// A collection groups series and has no order, so this is the same grid of covers a library
/// uses rather than the numbered run a reading list needs.
struct KavitaCollectionView: View {
    @Environment(\.theme) private var theme

    let server: KavitaPage
    let collectionID: Int
    let title: String
    /// This server's own reading lists, passed through to each chapter list.
    var lists: [ServerShelf] = []
    /// Where a pulled position is written. See `KavitaSync.pull`.
    var progress: ProgressStore?
    let onOpen: (Publication, URL) -> Void

    @State private var series: [KavitaSeries] = []

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: StoryArcSpace.md)]

    var body: some View {
        let client = KavitaClient(address: server.address)
        ScrollView {
            LazyVGrid(columns: columns, spacing: StoryArcSpace.md) {
                ForEach(series) { each in
                    NavigationLink {
                        KavitaChapterList(
                            client: client,
                            series: each,
                            sourceId: server.id,
                            store: KavitaProgressStore(),
                            progress: progress,
                            lists: lists,
                            onOpen: onOpen
                        )
                    } label: {
                        KavitaSeriesCell(series: each, client: client)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard series.isEmpty else { return }
            series = (try? await client.collected(collectionID)) ?? []
        }
    }
}

/// The entries in one of a server's reading lists, in the server's order.
///
/// Numbered, because the order is the point. A collection has none and this does.
struct KavitaListView: View {
    @Environment(\.theme) private var theme

    let server: KavitaPage
    let listID: Int
    let title: String
    let onOpen: (Publication, URL) -> Void

    @State private var items: [KavitaReadingListItem] = []
    @State private var fetching: Int?

    var body: some View {
        List(items) { entry in
            Button {
                Task { await open(entry) }
            } label: {
                HStack(spacing: StoryArcSpace.sm) {
                    Text(verbatim: "\(entry.order + 1)")
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)

                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(entry.displayName)
                            .foregroundStyle(theme.palette.textPrimary)
                        if let series = entry.seriesName, series != entry.displayName {
                            Text(series)
                                .textRole(.footnote)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if fetching == entry.chapterId { ProgressView() }
                }
                // Without this the row is only tappable where its text is, and the empty
                // half of a wide row does nothing.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(fetching != nil)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard items.isEmpty else { return }
            let client = KavitaClient(address: server.address)
            items = ((try? await client.readingListItems(listID)) ?? [])
                .sorted { $0.order < $1.order }
        }
    }

    private func open(_ entry: KavitaReadingListItem) async {
        fetching = entry.chapterId
        defer { fetching = nil }

        let client = KavitaClient(address: server.address)
        guard let fetched = try? await client.chapter(entry.chapterId),
              let file = kavitaCacheFile(
                  chapterId: entry.chapterId,
                  mediaType: fetched.mediaType,
                  named: entry.seriesName.map { "\($0) \(entry.chapterId)" }
              ),
              (try? fetched.bytes.write(to: file, options: .atomic)) != nil,
              let publication = try? await PublicationIndexer.index(
                  fileAt: file,
                  catalogueSeries: entry.seriesName
              )
        else { return }
        onOpen(publication, file)
    }
}
