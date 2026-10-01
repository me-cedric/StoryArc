import SwiftUI

internal import DesignSystem
internal import Formats
import Kavita
import Persistence
import StoryArcCore

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
    /// Where an opened entry's first position is written. See `seedKavitaOpen`.
    var progress: ProgressStore?
    let onOpen: (Publication, URL) -> Void

    /// Edits this device has made that the server has not taken yet, "visible on the list".
    /// Task 7.6: read here, as Android's `KavitaListScreen` already does, rather than passed
    /// in — a caller that forgot to (`HomeShelvesRow` did) left every pending row invisible.
    private var pending: [ShelfEdit] {
        ShelfEditStore().queue().pending(for: ShelfKey(sourceID: server.id, shelfID: listID))
    }

    @State private var items: [KavitaReadingListItem] = []
    @State private var fetching: Int?
    /// The entry whose last open failed, and why. An alert rather than a line in the list: the
    /// reader who tapped entry forty is looking at entry forty, not at the top of the list.
    @State private var openFailure: (title: String, reason: String)?

    /// The order this device has given the list and the server has not taken yet.
    ///
    /// Read from the same queue a failed position waits in. Empty means the server holds the
    /// reader's order already, which is the ordinary case.
    @State private var wanted: [Int] = []

    /// The push this view started last, so the next one waits for it.
    ///
    /// Kavita moves an entry by position, and a position only means anything against the
    /// order the server is in. Two drags a second apart would otherwise plan against the
    /// same read and land interleaved, leaving the list in an order nobody asked for.
    @State private var pushing: Task<Void, Never>?

    /// The server's entries in the reader's order, with the outstanding ones after them.
    ///
    /// ``ShelfSync`` and ``ShelfMerge`` decide both orders, so a test can assert them without
    /// a server. Internal, not private, for exactly that test.
    var rows: [ShelfEntry] {
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

    /// How many entries this list has finished, or nil when the server said nothing.
    private var counted: ServerListProgress.Counted? {
        ServerListProgress.summary(items.map { (read: $0.pagesRead, total: $0.pagesTotal) })
    }

    var body: some View {
        List {
            if let counted {
                // `collections-and-reading-lists`: a list "shows how many entries are
                // finished and where the user's position is". One sentence above the rows,
                // as the local list's own screen already draws it, and absent when the
                // server said nothing about any entry rather than claiming none are done.
                Text("shelves.list.progress \(counted.finished) \(counted.of)", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
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
                    // order, so it cannot be dragged into one, or removed from it.
                    .moveDisabled(row.isPending)
                    .deleteDisabled(row.isPending)
            }
            .onMove { offsets, destination in reorder(offsets, to: destination) }
            // Task 12.6: the swipe and the edit-mode control a local list already offers.
            .onDelete { remove($0) }
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
        .alert(
            openFailure.map { Text("kavita.open.failed \($0.title)", bundle: .module) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { openFailure != nil }, set: { if !$0 { openFailure = nil } })
        ) {
            Button { openFailure = nil } label: { Text("library.import.dismiss", bundle: .module) }
        } message: {
            Text(openFailure?.reason ?? "")
        }
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

                    // The library's own cover shape, at a row's height. Decorative: the row
                    // says what it is in one merged label below, so a description here would
                    // read it twice.
                    EntryPoster(chapterID: Int(row.id), address: server.address)

                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(row.title)
                            .foregroundStyle(theme.palette.textPrimary)
                        if row.isPending {
                            // Grey rather than red: an unsent edit is offline, and
                            // `sources` makes offline a normal state.
                            Text("shelves.pending.entry", bundle: .module)
                                .textRole(.footnote)
                                .foregroundStyle(StoryArcColor.Status.offline)
                        } else if let beneath = beneath(row) {
                            // One line rather than two: the row is a list entry, and a
                            // second stacked line under every title turns the order into a
                            // wall.
                            Text(beneath)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said(index: index, row: row))
    }

    /// The state of one row, or `.unknown` for an entry the server has not heard of.
    private func progress(_ row: ShelfEntry) -> ServerListProgress.State {
        guard let entry = items.first(where: { String($0.chapterId) == row.id }) else {
            return .unknown
        }
        return ServerListProgress.of(pagesRead: entry.pagesRead, pagesTotal: entry.pagesTotal)
    }

    /// The series and the read state, joined, or nil when there is neither to draw.
    ///
    /// An unread entry carries no badge, as an unread publication carries none in the
    /// library. It says so in ``said(index:row:)`` instead.
    private func beneath(_ row: ShelfEntry) -> String? {
        let entry = items.first(where: { String($0.chapterId) == row.id })
        let series = entry?.seriesName.flatMap { $0 == entry?.displayName ? nil : $0 }
        let drawn: String? = switch progress(row) {
        case .finished:
            String(localized: "library.readState.finished", bundle: .module, locale: .storyArc)
        case let .part(percent):
            String(localized: "library.cell.progress \(percent)", bundle: .module, locale: .storyArc)
        case .unread, .unknown:
            nil
        }
        let parts = [series, drawn].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the row is to a reader who cannot see it: its place in the order, what it is,
    /// and its read state in the library's own words — including "Unread", which is the one
    /// state with nothing to look at.
    private func said(index: Int, row: ShelfEntry) -> String {
        var parts = ["\(index + 1).", row.title]
        if let beneath = beneath(row) {
            parts.append(beneath)
        } else if progress(row) == .unread {
            parts.append(
                String(localized: "library.readState.unread", bundle: .module, locale: .storyArc)
            )
        }
        return parts.joined(separator: " ")
    }

    /// Applies a drag, and owes the server the order it produced.
    ///
    /// The rows move first and the send is attempted after, which is the order
    /// `collections-and-reading-lists` asks for — the edit is "applied locally, marked
    /// pending, and pushed on reconnection". ``KavitaSync/reorder(_:to:on:to:in:)`` writes it
    /// down before it tries, so a refused send is a queue entry rather than a lost order.
    private func reorder(_ offsets: IndexSet, to destination: Int) {
        let held = rows.filter { !$0.isPending }.map(\.id)
        // Task 7.4: checked against the order the reader saw before this drag.
        guard let from = offsets.first, let drag = KavitaSync.dragged(held, from: from, to: destination) else {
            return
        }
        let order = drag.order
        items = order.compactMap { id in items.first { $0.chapterId == id } }
            + items.filter { !order.contains($0.chapterId) }

        let previous = pushing
        pushing = Task {
            await previous?.value
            let store = KavitaProgressStore()
            await KavitaSync.reorder(
                listID,
                to: order,
                on: server.id,
                to: server.address,
                in: store,
                baseline: drag.baseline,
                // Task 7.4: dropped rather than sent over a server that moved since.
                onOrderConflict: { KavitaSync.noteOrderConflict(sourceID: server.id, listID: $0, shelfName: title) }
            )
            wanted = KavitaSync.wantedOrder(of: listID, on: server.id, in: store)
            guard wanted.isEmpty else { return }
            // A stale drag was dropped, so the server's order wins and the rows show it again.
            let client = KavitaClient(address: server.address)
            if let kept = await KavitaSync.settledRows(listID, sent: order, through: client) { items = kept }
        }
    }

    /// Takes entries out of the list here first, then owes the server their removal.
    ///
    /// Sent after the push before it, for the reason `pushing` gives. ``KavitaSync``
    /// holds a removal the server does not take, as it holds a drag.
    private func remove(_ offsets: IndexSet) {
        let leaving = KavitaSync.leaving(offsets, of: rows, in: items)
        items.removeAll { leaving.contains($0) }
        let previous = pushing
        pushing = Task {
            await previous?.value
            let store = KavitaProgressStore()
            for entry in leaving {
                await KavitaSync.removeEntry(entry, from: listID, on: server.id, to: server.address, in: store)
            }
        }
    }

    /// Internal, not private: a test calls this directly, as `KavitaOpenFailureTests` does
    /// for `entryRow`'s own fetch. Task 7.3 adds `ServerListContext.opened(_:)` to this.
    func open(_ entry: KavitaReadingListItem) async {
        fetching = entry.chapterId
        defer { fetching = nil }

        let opening = await KavitaEntryOpening.attempt(
            entry,
            sourceId: server.id,
            store: KavitaProgressStore(),
            from: KavitaClient(address: server.address)
        )
        if case let .opened(publication, file) = opening {
            await seedKavitaOpen(publication, pagesRead: entry.pagesRead, of: entry.pagesTotal, into: progress)
            // Task 7.3: remembered before the reader opens, so its own next-entry offer
            // can ask this list rather than the local one.
            ServerListContext.opened(
                .init(
                    serverId: server.id,
                    serverAddress: server.address,
                    listId: listID,
                    entries: items,
                    position: items.firstIndex(of: entry) ?? 0
                )
            )
            onOpen(publication, file)
        }
        openFailure = opening.reason(server: server.title).map { (entry.displayName, $0) }
    }
}
