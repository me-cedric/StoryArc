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
        var collectionCapable: [KavitaPage] = []
        for source in registry.sources {
            guard let page = KavitaPage(source: source, credentials: credentials) else { continue }
            let client = KavitaClient(address: page.address)
            // Asked and answered on its own. A server can answer one of these and not the
            // other, so a refused collections request must not cost the reader that server's
            // reading lists as well.
            if let collections = try? await client.collections() {
                collectionCapable.append(page)
                found += collections.map {
                    ServerShelf(server: page, id: $0.id, title: $0.title, isList: false)
                }
            }
            // Answered rather than non-empty: a server that has no lists yet is exactly the
            // one a reader is most likely to want to copy their first list onto.
            if let lists = try? await client.readingLists() {
                listCapable.append(page)
                found += lists.map {
                    ServerShelf(server: page, id: $0.id, title: $0.title, isList: true)
                }
            }
        }
        return ServerShelves(
            shelves: found,
            listCapable: listCapable,
            collectionCapable: collectionCapable
        )
    }
}

/// What one round of asking every server produced.
struct ServerShelves: Sendable {
    let shelves: [ServerShelf]

    /// The servers that answered when asked for their reading lists — reachable, and able to
    /// hold one. A server that did not answer is simply not offered.
    let listCapable: [KavitaPage]

    /// The same question about collections, kept apart from the answer about lists because
    /// they are two different capabilities and a server can answer one and not the other.
    var collectionCapable: [KavitaPage] = []
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
    /// Edits this device has made that the server has not taken yet.
    ///
    /// `collections-and-reading-lists` requires an edit made while the server was
    /// unreachable to be "applied locally" and its pending state to be "visible on the
    /// list". Passed in rather than read here, so the rows and the badge on the shelf above
    /// them come from one reading of the queue.
    var pending: [ShelfEdit] = []
    let onOpen: (Publication, URL) -> Void

    @State private var items: [KavitaReadingListItem] = []
    @State private var fetching: Int?

    /// The order this device has given the list and the server has not taken yet.
    ///
    /// Read from the same queue a failed position waits in. Empty means the server holds the
    /// reader's order already, which is the ordinary case.
    @State private var wanted: [Int] = []

    /// The server's entries in the reader's order, with the outstanding ones after them.
    ///
    /// ``ShelfSync`` and ``ShelfMerge`` decide both orders, so a test can assert them without
    /// a server.
    private var rows: [ShelfEntry] {
        ShelfMerge.projecting(
            remote: ShelfSync.arranged(
                items.map {
                    ShelfEntry(id: String($0.chapterId), title: $0.displayName, isPending: false)
                },
                by: wanted.map(String.init)
            ),
            pending: pending
        )
    }

    var body: some View {
        List {
            if !wanted.isEmpty {
                // `collections-and-reading-lists` wants a pending edit "visible on the list".
                // An order is one edit about every row, so it is said once, above them.
                Text("shelves.pending.order", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(StoryArcColor.Status.offline)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                entryRow(index: index, row: row)
                    // An entry the server has not heard of has no place in the server's own
                    // order, so it cannot be dragged into one.
                    .moveDisabled(row.isPending)
            }
            .onMove { offsets, destination in reorder(offsets, to: destination) }
        }
        #if os(iOS)
        // Reordering by drag needs edit mode, and `EditButton` is the control iOS readers
        // already know — the same one ``ReadingListDetail`` gives a local list.
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        #endif
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            wanted = KavitaSync.wantedOrder(of: listID, on: server.id, in: KavitaProgressStore())
            guard items.isEmpty else { return }
            let client = KavitaClient(address: server.address)
            items = ((try? await client.readingListItems(listID)) ?? [])
                .sorted { $0.order < $1.order }
        }
    }

    /// One row of the list.
    @ViewBuilder
    private func entryRow(index: Int, row: ShelfEntry) -> some View {
        Button {
            guard let entry = items.first(where: { String($0.chapterId) == row.id }) else {
                return
            }
            Task { await open(entry) }
        } label: {
                HStack(spacing: StoryArcSpace.sm) {
                    Text(verbatim: "\(index + 1)")
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)

                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(row.title)
                            .foregroundStyle(theme.palette.textPrimary)
                        if row.isPending {
                            // Grey rather than red: an unsent edit is offline, and
                            // `sources` makes offline a normal state.
                            Text("shelves.pending.entry", bundle: .module)
                                .textRole(.footnote)
                                .foregroundStyle(StoryArcColor.Status.offline)
                        } else if let entry = items.first(where: { String($0.chapterId) == row.id }),
                                  let series = entry.seriesName,
                                  series != entry.displayName {
                            Text(series)
                                .textRole(.footnote)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if fetching.map({ String($0) == row.id }) == true { ProgressView() }
                }
            // Without this the row is only tappable where its text is, and the empty
            // half of a wide row does nothing.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A pending entry cannot be opened from here: the server is what would hand the
        // file over, and it has not heard of this entry yet.
        .disabled(fetching != nil || row.isPending)
    }

    /// Applies a drag, and owes the server the order it produced.
    ///
    /// The rows move first and the send is attempted after, which is the order
    /// `collections-and-reading-lists` asks for — the edit is "applied locally, marked
    /// pending, and pushed on reconnection". ``KavitaSync/reorder(_:to:on:to:in:)`` writes it
    /// down before it tries, so a refused send is a queue entry rather than a lost order.
    private func reorder(_ offsets: IndexSet, to destination: Int) {
        let held = rows.filter { !$0.isPending }.map(\.id)
        guard let from = offsets.first, from < held.count, destination <= held.count else {
            return
        }
        var next = held
        next.insert(next.remove(at: from), at: destination > from ? destination - 1 : destination)
        let order = next.compactMap(Int.init)
        items = order.compactMap { id in items.first { $0.chapterId == id } }
            + items.filter { !order.contains($0.chapterId) }

        Task {
            let store = KavitaProgressStore()
            await KavitaSync.reorder(
                listID,
                to: order,
                on: server.id,
                to: server.address,
                in: store
            )
            wanted = KavitaSync.wantedOrder(of: listID, on: server.id, in: store)
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
