internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What is in a collection.
///
/// A grid, because a collection is a shelf and a shelf is looked at rather than worked
/// through. Its reading list counterpart is a list, for the opposite reason.
struct CollectionDetail: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    let id: UUID

    /// Whether the reader is choosing which cover this collection wears.
    @State private var isChoosingCover = false

    var body: some View {
        let collection = model.shelves.collections.first { $0.id == self.id }
        let members = model.publications.filter { collection?.members.contains($0.id) == true }

        ScrollView {
            if members.isEmpty {
                Text("shelves.collection.empty", bundle: .module)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(StoryArcSpace.xl)
            } else {
                VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                    ShelfOnDeviceLine(members, model: model)
                        .padding(.horizontal, StoryArcSpace.gutter)

                    CoverGrid(
                        publications: members,
                        model: model,
                        onRemoveFromShelf: { model.remove(Set([$0.id]), fromCollection: self.id) }
                    )
                }
            }
        }
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(collection?.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // `collections-and-reading-lists` asks for a whole collection to be downloaded or
        // marked read. Membership rather than the grid: a publication whose file has gone is
        // still a member, and marking it read is still what the reader asked for.
        .shelfBulkActions(model: model, members: collection?.members ?? [])
        // "unless the user sets a specific one". The offer lives here rather than on the
        // shelf card, because choosing between four covers and one is a question about what
        // is inside the collection, and this is the screen showing what is inside it. A
        // collection holding nothing has nothing to offer, so it does not ask.
        .toolbar {
            if collection?.members.isEmpty == false {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isChoosingCover = true
                    } label: {
                        Label {
                            Text("shelves.cover", bundle: .module)
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isChoosingCover) {
            if let collection {
                ShelfCoverPicker(model: model, collection: collection)
            }
        }
    }
}

/// What is in a reading list, in the order it is meant to be read.
///
/// A list with the order visible and draggable, because `collections-and-reading-lists`
/// makes the order the meaning: "the new order persists", and the next entry offered at the
/// end of one is the next in *this* order rather than the next in a series.
struct ReadingListDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let model: LibraryModel
    let id: UUID

    /// ``ShelfCover``'s own row-scale thumbnail — small enough that a hundred entries cost
    /// a hundred small decodes rather than a hundred full covers.
    private static let thumbnailWidth: CGFloat = 40

    /// How the reader has asked to see the list, for as long as they are looking at it.
    ///
    /// `library-browsing` gives a chosen order "that session" and no longer, and this is the
    /// shortest honest reading of it: leaving the list ends the session, and coming back
    /// lands on the order the list carries — which is the order that means something.
    /// `@State` rather than anything stored, because the alternative is a preference nobody
    /// asked for that quietly outlives the evening it was set in.
    @State private var order = ListOrder.curated

    var body: some View {
        let list = model.shelves.lists.first { $0.id == self.id }
        let entries = list?.entries ?? []
        let finished = model.finishedPublications
        let position = list?.position { finished.contains($0) } ?? 0
        // What is drawn, and what each row is numbered. The list keeps its own order
        // throughout: `shown` is a new sequence and `numbers` is read off `entries`.
        // The reader's language, for the reason ``LibraryModel/rebuild()`` gives: a reading
        // list sorted by title has to collate the way the shelf does, and the shelf now
        // collates in the chosen language rather than the device's.
        let shown = ListOrdering.arrange(
            entries,
            by: order,
            publications: model.publications,
            locale: .storyArc
        ) { LibraryIndex.Progress.of(model.progress[$0.id]) }
        let numbers = ListOrdering.positions(in: entries)

        List {
            if entries.isEmpty {
                Text("shelves.list.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                Section {
                    ForEach(shown, id: \.self) { entry in
                        row(
                            entry,
                            number: numbers[entry] ?? 0,
                            isFinished: finished.contains(entry)
                        )
                        // Dragging is off while a sort is overriding the list. `ListOrder`
                        // says why it has to be: a drag reports where it landed *as drawn*,
                        // and that position written into the curated order would scramble
                        // the thing the reader was promised would not change.
                        .moveDisabled(!order.allowsReordering)
                    }
                    .onMove { offsets, destination in
                        guard order.allowsReordering,
                              let from = offsets.first, from < entries.count
                        else { return }
                        model.move(entries[from], to: destination, inList: self.id)
                    }
                    // Removing is by identity rather than by position, so it is safe in any
                    // order — but the offsets are into what is *drawn*, which is `shown`.
                    .onDelete { offsets in
                        for index in offsets where index < shown.count {
                            model.remove(shown[index], fromList: self.id)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        // `collections-and-reading-lists`: a list "shows how many entries are
                        // finished and where the user's position is".
                        Text("shelves.list.progress \(position) \(entries.count)", bundle: .module)
                        ShelfOnDeviceLine(
                            entries: entries,
                            members: entries.compactMap { entry in
                                model.publications.first { $0.id == entry }
                            },
                            model: model
                        )
                        // `library-browsing`: the curated order is "labelled as such — not
                        // alphabetical". A toolbar menu on iOS draws its glyph and not its
                        // title, so the name of the order goes where the reader is already
                        // reading — under the count, on its own line so the largest text
                        // size wraps it rather than squeezing it against the count.
                        Text(order.titleKey, bundle: .module)
                    }
                }
            }
        }
        .navigationTitle(list?.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // The library's own sort control, in the shape a list needs: the curated order
            // is one of the answers rather than a separate idea.
            ToolbarItem(placement: .primaryAction) {
                ListOrderMenu(order: $order)
            }
            #if os(iOS)
            // Reordering by drag needs edit mode, and `EditButton` is the control iOS
            // readers already know. It does not exist on macOS, where the package builds
            // only so the pure targets can be tested on the host.
            //
            // It gives its place to the way back while a sort is overriding the list: the
            // two are never both useful, the order cannot be edited from there anyway, and
            // `library-browsing` asks the return to be one tap rather than one tap into a
            // menu.
            if order.allowsReordering {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            #endif
            if !order.isCurated {
                ToolbarItem(placement: .primaryAction) {
                    Button { order = .curated } label: {
                        Label {
                            Text("shelves.list.order", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                }
            }
        }
        // The whole list at once, per `collections-and-reading-lists`. Its entries rather
        // than the publications behind them: an entry whose source dropped the publication
        // is skipped by the action itself rather than left out of what the reader asked for.
        //
        // The list itself goes too: the same requirement offers to copy a local one onto a
        // server, and the offer belongs where the reader is looking at the list.
        .shelfBulkActions(model: model, members: Set(entries), promoting: list)
    }

    /// The server whose list just refused a row's publication, if one did.
    @State private var refusedServer: String?
    @State private var restarting: Publication?

    /// Artwork that has arrived for a row, keyed by the entry it belongs to.
    ///
    /// `collections-and-reading-lists`' delta: "each entry shows the publication's own cover
    /// beside its position in the list" — the same fetch ``ShelfCover`` already does for the
    /// shelf's own artwork, kept on the detail screen so a list of a hundred entries asks the
    /// library for exactly the covers it draws.
    @State private var covers: [String: CGImage] = [:]

    @ViewBuilder
    private func row(_ entry: String, number: Int, isFinished: Bool) -> some View {
        let publication = model.publications.first { $0.id == entry }
        let fraction = publication.flatMap { isFinished ? nil : model.readFraction(of: $0) }
        let state = ReadingListRowState.of(
            isAvailable: publication != nil,
            isFinished: isFinished,
            fraction: fraction
        )

        // The page, not the reader — which is what Android's equivalent does
        // (`AppScreens.kt`) and what `publication-detail` asks of "every surface that shows
        // a publication". The rule's own exception is a **resume affordance**, and this row
        // is not one: it carries a number, a title, a cover and a read state, with no
        // *Continue* wording. Nothing about it says a reader has already decided to read
        // this one now, so sending them straight into the reader was the app deciding for
        // them.
        //
        // An entry whose publication is gone stays disabled below, so the destination is
        // always a publication the library still holds.
        NavigationLink(value: publication.map(PublicationRoute.init)) {
            HStack(spacing: StoryArcSpace.md) {
                Text("\(number)")
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
                    .frame(minWidth: StoryArcSpace.lg, alignment: .trailing)

                // The position stays legible without it — ``thumbnail`` draws a plain well
                // rather than nothing while a cover is missing or has not arrived, so an
                // entry never loses its place in the row for lacking one.
                thumbnail(for: entry)
                    .frame(width: Self.thumbnailWidth, height: Self.thumbnailWidth * 1.5)
                    .clipShape(.rect(cornerRadius: StoryArcRadius.sm))

                VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                    Text(publication?.displayTitle ?? entry)
                        .foregroundStyle(
                            publication == nil ? theme.palette.textSecondary : theme.palette.textPrimary
                        )

                    if publication == nil {
                        // `collections-and-reading-lists`: an entry whose source no longer
                        // has the publication "remains in the list, marked unavailable, and
                        // does not break the ordering or the next flow". Removing it would
                        // renumber everything after it.
                        Text("shelves.list.unavailable", bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(StoryArcColor.Status.offline)
                    } else if let drawn = state.drawn {
                        // An unread entry draws nothing here, as an unread publication draws
                        // nothing in the library's own grid — ``state.spoken`` still names
                        // it, to a reader who cannot see the absence of a badge.
                        Text(drawn)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(publication == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [publication?.displayTitle ?? entry, state.spoken].joined(separator: ", ")
        )
        .task(id: entry) {
            guard covers[entry] == nil, let publication else { return }
            let side = Int(Self.thumbnailWidth * displayScale)
            covers[entry] = await model.cover(for: publication, maxPixelSize: side)
        }
        // `library-browsing`'s *A publication's actions wherever it is drawn*: a reading
        // list's own row had none at all, only the swipe this screen already offered for
        // removal. An entry the library no longer holds a publication for has nothing a
        // menu could act on, so it draws none.
        .contextMenu {
            if let publication {
                PublicationActionMenu(
                    model: model,
                    publication: publication,
                    onRemoveFromShelf: { model.remove(entry, fromList: self.id) },
                    onRefused: { refusedServer = $0 },
                    onRestart: { restarting = publication }
                )
            }
        }
        .restartConfirmation($restarting, model: model)
        .refusedByServer($refusedServer, model: model, publication: publication)
    }

    /// The row's own cover, or a plain well while one has not arrived.
    ///
    /// Decorative: the row's merged accessibility label already states the title and the
    /// read state, so a label here would read the title twice.
    @ViewBuilder
    private func thumbnail(for entry: String) -> some View {
        if let image = covers[entry] {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            theme.palette.surfaceRaised
        }
    }
}

/// What a reading list's row draws beneath its title, and what it says to a screen reader.
///
/// `collections-and-reading-lists`' delta: "each entry states its own read state — finished,
/// part-read with the position reached, or unread — in the same terms the library uses for a
/// publication". Free of the view so a test can call it directly, and shared in shape with
/// Android's `entryReadState` even though each platform reaches its own strings for it.
///
/// An unread entry draws nothing, the rule the library's own grid cell and
/// ``KavitaShelfViews``' server row both already keep — nothing on a shelf says "unread" out
/// loud through a badge. ``spoken`` still names it, since a screen reader is told what a
/// sighted reader would see by its absence.
struct ReadingListRowState: Equatable {
    /// What is drawn beneath the title, or nil to draw nothing.
    let drawn: String?
    /// What a screen reader is told, which never withholds "unread" the way `drawn` does.
    let spoken: String

    static func of(isAvailable: Bool, isFinished: Bool, fraction: Double?) -> ReadingListRowState {
        guard isAvailable else {
            return ReadingListRowState(
                drawn: nil,
                spoken: String(localized: "shelves.list.unavailable", bundle: .module, locale: .storyArc)
            )
        }
        let drawn: String? =
            if isFinished {
                String(localized: "library.cell.finished", bundle: .module, locale: .storyArc)
            } else if let fraction {
                String(
                    localized: "library.cell.progress \(Int(fraction * 100))",
                    bundle: .module,
                    locale: .storyArc
                )
            } else {
                nil
            }
        let spoken = drawn ?? String(
            localized: "library.readState.unread",
            bundle: .module,
            locale: .storyArc
        )
        return ReadingListRowState(drawn: drawn, spoken: spoken)
    }
}
