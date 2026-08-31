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
                CoverGrid(publications: members, model: model)
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

    let model: LibraryModel
    let id: UUID

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
        let shown = ListOrdering.arrange(
            entries,
            by: order,
            publications: model.publications
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

    @ViewBuilder
    private func row(_ entry: String, number: Int, isFinished: Bool) -> some View {
        let publication = model.publications.first { $0.id == entry }

        // The page, not the reader — which is what Android's equivalent does
        // (`AppScreens.kt`) and what `publication-detail` asks of "every surface that shows
        // a publication". The rule's own exception is a **resume affordance**, and this row
        // is not one: it carries a number, a title and a finished mark, with no cover, no
        // progress and no *Continue* wording. Nothing about it says a reader has already
        // decided to read this one now, so sending them straight into the reader was the app
        // deciding for them.
        //
        // An entry whose publication is gone stays disabled below, so the destination is
        // always a publication the library still holds.
        NavigationLink(value: publication.map(PublicationRoute.init)) {
            HStack(spacing: StoryArcSpace.md) {
                Text("\(number)")
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
                    .frame(minWidth: StoryArcSpace.lg, alignment: .trailing)

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
                    }
                }

                Spacer(minLength: 0)

                if isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(StoryArcColor.Status.success)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(publication == nil)
    }
}
