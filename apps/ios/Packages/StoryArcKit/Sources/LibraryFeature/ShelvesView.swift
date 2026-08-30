public import SwiftUI

internal import DesignSystem
internal import Persistence
public import StoryArcCore

/// Collections and reading lists, in one place.
///
/// `collections-and-reading-lists` requires local and server groupings to appear "in one
/// list, each labelled with its source" rather than segregated. Two sections here because
/// they are two different ideas, not two different origins — the origin is a label on a row.
///
/// Drawn as two shelves of covers rather than two lists of names. §3.6 of the revamp: "a
/// collection with no artwork is a folder listing", and a folder listing is the one thing
/// this app is not. Each section leads with the sentence that says what its shelves *are*,
/// because *collection* and *reading list* are words a reader has to be taught once.
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

    /// Edits owed to a server, so a shelf can say so and a conflict can be said once.
    ///
    /// Read into the view rather than asked for per card: the badge and the notice come out
    /// of the same reconciliation, and a card that fetched its own would disagree with the
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

    /// The shelf lattice.
    ///
    /// Adaptive rather than a column count, for the reason ``CoverGrid`` gives: a fixed
    /// count gives a phone postage stamps and an iPad a wall. The minimum is wider than a
    /// publication's because a shelf is a composite of four covers, and four covers below
    /// about 150 pt stop being four covers.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: StoryArcSpace.lg, alignment: .top)]
    }

    public var body: some View {
        let shelves = model.shelves
        let serverCollections = serverShelves.filter { !$0.isList }
        let serverLists = serverShelves.filter(\.isList)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: StoryArcSpace.xxl) {
                collections(shelves.collections, server: serverCollections)
                lists(shelves.lists, server: serverLists)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.lg)
        }
        .background(theme.palette.surfaceCanvas)
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
        .toolbar { ToolbarItem(placement: .primaryAction) { newMenu } }
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

    // MARK: Sections

    @ViewBuilder
    private func collections(
        _ local: [PublicationCollection],
        server: [ServerShelf]
    ) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            heading("shelves.collections", about: "shelves.collections.about")

            if local.isEmpty && server.isEmpty {
                makeShelfButton("shelves.new.collection") {
                    draftName = ""
                    creating = .collection
                }
            }

            if !local.isEmpty || !server.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: StoryArcSpace.xl) {
                    ForEach(local) { collection in
                        NavigationLink {
                            CollectionDetail(model: model, id: collection.id, onOpen: onOpen)
                        } label: {
                            // `collections-and-reading-lists` gives a collection with
                            // contents a cover "composite of its first four member covers",
                            // and the artwork is the interface.
                            ShelfCard(
                                model: model,
                                title: collection.name,
                                subtitle: subtitle(count: collection.members.count, origin: collection.origin),
                                tiles: CompositeCover.tiles(of: collection)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton { model.delete(collection: collection.id) } }
                    }
                    ForEach(server) { shelf in
                        NavigationLink {
                            KavitaCollectionView(
                                server: shelf.server,
                                collectionID: shelf.id,
                                title: shelf.title,
                                onOpen: onOpen
                            )
                        } label: {
                            serverCard(shelf)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lists(_ local: [ReadingList], server: [ServerShelf]) -> some View {
        let finished = model.finishedPublications

        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            heading("shelves.lists", about: "shelves.lists.about")

            if local.isEmpty && server.isEmpty {
                makeShelfButton("shelves.new.list") {
                    draftName = ""
                    creating = .list
                }
            }

            if !local.isEmpty || !server.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: StoryArcSpace.xl) {
                    ForEach(local) { list in
                        NavigationLink {
                            ReadingListDetail(model: model, id: list.id, onOpen: onOpen)
                        } label: {
                            // A list's tiles are its first four entries in *its* order, and
                            // its rail is how far through that order the reader is — the
                            // two things that make it a list rather than a bag.
                            ShelfCard(
                                model: model,
                                title: list.name,
                                subtitle: subtitle(count: list.entries.count, origin: list.origin),
                                tiles: ShelfCover.tiles(of: list),
                                progress: ShelfProgress(
                                    done: list.position { finished.contains($0) },
                                    total: list.entries.count
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton { model.delete(list: list.id) } }
                    }
                    ForEach(server) { shelf in
                        NavigationLink {
                            KavitaListView(
                                server: shelf.server,
                                listID: shelf.id,
                                title: shelf.title,
                                pending: edits.pending(for: ShelfSync.key(shelf)),
                                onOpen: onOpen
                            )
                        } label: {
                            serverCard(shelf, pending: edits.pending(for: ShelfSync.key(shelf)).count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    /// A section's name and the one sentence that says what its shelves are.
    ///
    /// §3.6 asks for Komga's metaphor in the copy — a collection groups what you like, a
    /// reading list is a playlist for books. Above the shelf rather than only in the empty
    /// state, because the reader who has never met the word is not always the reader who
    /// has none of them — and it *is* the empty state, because a second sentence saying
    /// there are none of something the line above has just defined tells the reader nothing
    /// the blank space below it does not.
    @ViewBuilder
    private func heading(_ title: LocalizedStringKey, about: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(title, bundle: .module)
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
            Text(about, bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// What an empty section offers instead of blank space.
    ///
    /// The sentence stays where ``heading(_:about:)`` puts it — repeating "no collections
    /// yet" under a line that has just explained what a collection is tells the reader
    /// nothing the blank space does not. What the blank space *was* missing is the way out:
    /// the only way to make a shelf was the `+` in the navigation bar, which is a control a
    /// reader has to already know about on the one screen where they demonstrably do not.
    @ViewBuilder
    private func makeShelfButton(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.bordered)
        .padding(.top, StoryArcSpace.xs)
    }

    /// A shelf that lives in an online library.
    ///
    /// No composite: its members are chapters on a server this device has not necessarily
    /// opened, so there is no local artwork to compose from and a half-loaded mosaic would
    /// be worse than a clean blank.
    @ViewBuilder
    private func serverCard(_ shelf: ServerShelf, pending: Int = 0) -> some View {
        ShelfCard(
            model: model,
            title: shelf.title,
            subtitle: shelf.server.title,
            tiles: [],
            pending: pending
        )
    }

    @ViewBuilder
    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label {
                Text("shelves.delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    @ViewBuilder
    private var newMenu: some View {
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
