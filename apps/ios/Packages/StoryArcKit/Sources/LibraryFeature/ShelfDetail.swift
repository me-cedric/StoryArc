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
    let onOpen: (Publication, URL) -> Void

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
                CoverGrid(
                    publications: members,
                    continueReading: [],
                    model: model,
                    onOpen: { publication in
                        if let url = model.location(of: publication) { onOpen(publication, url) }
                    }
                )
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
    let onOpen: (Publication, URL) -> Void

    var body: some View {
        let list = model.shelves.lists.first { $0.id == self.id }
        let entries = list?.entries ?? []
        let finished = model.finishedPublications
        let position = list?.position { finished.contains($0) } ?? 0

        List {
            if entries.isEmpty {
                Text("shelves.list.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                        row(entry, number: index + 1, isFinished: finished.contains(entry))
                    }
                    .onMove { offsets, destination in
                        guard let from = offsets.first, from < entries.count else { return }
                        model.move(entries[from], to: destination, inList: self.id)
                    }
                    .onDelete { offsets in
                        for index in offsets where index < entries.count {
                            model.remove(entries[index], fromList: self.id)
                        }
                    }
                } header: {
                    // `collections-and-reading-lists`: a list "shows how many entries are
                    // finished and where the user's position is".
                    Text("shelves.list.progress \(position) \(entries.count)", bundle: .module)
                }
            }
        }
        .navigationTitle(list?.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        // Reordering by drag needs edit mode, and `EditButton` is the control iOS readers
        // already know. It does not exist on macOS, where the package builds only so the
        // pure targets can be tested on the host.
        .toolbar { EditButton() }
        #endif
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

        Button {
            guard let publication, let url = model.location(of: publication) else { return }
            onOpen(publication, url)
        } label: {
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
