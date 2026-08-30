public import SwiftUI

internal import DesignSystem
public import Persistence
public import StoryArcCore

/// Collections and reading lists, in one place.
///
/// `collections-and-reading-lists` requires local and server groupings to appear "in one
/// list, each labelled with its source" rather than segregated. Two sections here because
/// they are two different ideas, not two different origins — the origin is a label on a row.
public struct ShelvesView: View {
    @Environment(\.theme) private var theme

    private let model: LibraryModel
    private let onOpen: (Publication, URL) -> Void

    @State private var creating: Kind?
    @State private var draftName = ""

    /// Every Kavita server's own collections and reading lists, once asked for.
    ///
    /// Fetched here rather than per row: the spec wants a server's collections "alongside
    /// local ones", which means inside the same two sections, and a section cannot be built
    /// from rows that each fetch their own.
    @State private var serverShelves: [ServerShelf] = []

    /// Edits owed to a server, so a row can say so and a conflict can be said once.
    ///
    /// Read into the view rather than asked for per row: the badge and the notice come out
    /// of the same reconciliation, and a row that fetched its own would disagree with the
    /// alert above it.
    @State private var edits = ShelfEditQueue()

    /// Which kind the "new" sheet is making.
    private enum Kind: String, Identifiable {
        case collection
        case list

        var id: String { rawValue }
    }

    public init(model: LibraryModel, onOpen: @escaping (Publication, URL) -> Void = { _, _ in }) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        let shelves = model.shelves

        List {
            let serverCollections = serverShelves.filter { !$0.isList }
            let serverLists = serverShelves.filter(\.isList)

            Section {
                // Empty only when neither half has anything: a server's collections make
                // this section not-empty just as a local one does.
                if shelves.collections.isEmpty, serverCollections.isEmpty {
                    Text("shelves.collections.none", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    ForEach(shelves.collections) { collection in
                        NavigationLink {
                            CollectionDetail(model: model, id: collection.id, onOpen: onOpen)
                        } label: {
                            HStack(spacing: StoryArcSpace.md) {
                                // `collections-and-reading-lists` gives a collection with
                                // contents a cover "composite of its first four member
                                // covers", and the artwork is the interface: a shelf of
                                // collections is a shelf of covers, not a list of names.
                                ShelfCover(model: model, collection: collection)
                                row(
                                    name: collection.name,
                                    count: collection.members.count,
                                    origin: collection.origin
                                )
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.delete(collection: shelves.collections[index].id)
                        }
                    }
                }
                ForEach(serverCollections) { shelf in
                    NavigationLink {
                        KavitaCollectionView(
                            server: shelf.server,
                            collectionID: shelf.id,
                            title: shelf.title,
                            onOpen: onOpen
                        )
                    } label: {
                        serverRow(shelf)
                    }
                }
            } header: {
                Text("shelves.collections", bundle: .module)
            }

            Section {
                if shelves.lists.isEmpty, serverLists.isEmpty {
                    Text("shelves.lists.none", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    ForEach(shelves.lists) { list in
                        NavigationLink {
                            ReadingListDetail(model: model, id: list.id, onOpen: onOpen)
                        } label: {
                            row(name: list.name, count: list.entries.count, origin: list.origin)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.delete(list: shelves.lists[index].id)
                        }
                    }
                }
                ForEach(serverLists) { shelf in
                    NavigationLink {
                        KavitaListView(
                            server: shelf.server,
                            listID: shelf.id,
                            title: shelf.title,
                            pending: edits.pending(for: ShelfSync.key(shelf)),
                            onOpen: onOpen
                        )
                    } label: {
                        serverRow(shelf, pending: edits.pending(for: ShelfSync.key(shelf)).count)
                    }
                }
            } header: {
                Text("shelves.lists", bundle: .module)
            }
        }
        .task {
            if serverShelves.isEmpty {
                serverShelves = await ServerShelf.all(
                    in: model.registry,
                    credentials: CredentialStore()
                )
            }
            // Outside the guard: what is owed, and what is still to be said about a conflict,
            // are worth reading every time this screen appears, not only the first.
            await reconcile()
        }
        .navigationTitle(Text("shelves.title", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        draftName = ""
                        creating = .collection
                    } label: {
                        Text("shelves.new.collection", bundle: .module)
                    }
                    Button {
                        draftName = ""
                        creating = .list
                    } label: {
                        Text("shelves.new.list", bundle: .module)
                    }
                } label: {
                    Label {
                        Text("shelves.new", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert(
            Text(creating == .list ? "shelves.new.list" : "shelves.new.collection", bundle: .module),
            isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } }),
            presenting: creating
        ) { kind in
            TextField(String(localized: "shelves.new.field", bundle: .module, locale: .storyArc), text: $draftName)
            Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            Button {
                switch kind {
                case .collection: model.create(collection: draftName)
                case .list: model.create(list: draftName)
                }
            } label: {
                Text("shelves.create", bundle: .module)
            }
        } message: { _ in
            // `collections-and-reading-lists`: "the storage location is stated at creation,
            // not discovered later". There is one location today, and saying so is what
            // makes the sentence true rather than merely unfalsified.
            Text("shelves.new.storedLocally", bundle: .module)
        }
        // `collections-and-reading-lists`: on a conflict "the user is told once what
        // changed". Dismissing it is what makes it once — the notice is deleted, not
        // hidden, so the next refresh has nothing left to raise.
        .alert(
            Text("shelves.conflict.title", bundle: .module),
            isPresented: Binding(get: { edits.nextNotice != nil }, set: { _ in }),
            presenting: edits.nextNotice
        ) { notice in
            Button {
                let store = ShelfEditStore()
                store.update { $0.acknowledging(notice.id) }
                edits = store.queue()
            } label: {
                Text("shelves.conflict.understood", bundle: .module)
            }
        } message: { notice in
            Text(
                "shelves.conflict.body \(notice.shelfName) \(notice.discarded.joined(separator: ", "))",
                bundle: .module
            )
        }
    }

    /// Asks every server list what it holds, settles what has landed, and pushes what has
    /// not — the "on reconnection" half of the offline rule, driven by the one moment this
    /// screen already knows a server answered.
    private func reconcile() async {
        let store = ShelfEditStore()
        await ShelfSync.reconcile(
            lists: serverShelves.filter(\.isList),
            store: store,
            progress: KavitaProgressStore()
        )
        edits = store.queue()
    }

    @ViewBuilder
    private func serverRow(_ shelf: ServerShelf, pending: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(shelf.title)
                .foregroundStyle(theme.palette.textPrimary)
            Text(shelf.server.title)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            // `collections-and-reading-lists`: "the pending state is visible on the list".
            // On the row as well as inside it, because a reader looking for what has not
            // gone out yet should not have to open every list to find it.
            if pending > 0 {
                Text("shelves.pending \(pending)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(StoryArcColor.Status.offline)
            }
        }
    }

    @ViewBuilder
    private func row(name: String, count: Int, origin: ShelfOrigin) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(name)
                .foregroundStyle(theme.palette.textPrimary)

            Text(subtitle(count: count, origin: origin))
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// The count, and where the grouping came from.
    private func subtitle(count: Int, origin: ShelfOrigin) -> String {
        let items = String(
            format: String(localized: "shelves.count \(count)", bundle: .module, locale: .storyArc),
            count
        )
        guard let sourceID = origin.sourceID,
              let source = model.registry[sourceID]
        else {
            return items
        }
        return "\(source.displayName) · \(items)"
    }
}
