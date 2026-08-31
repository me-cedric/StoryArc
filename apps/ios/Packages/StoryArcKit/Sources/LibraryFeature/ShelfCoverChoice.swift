internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What a collection can be given for a cover, and which of them it is wearing.
///
/// `collections-and-reading-lists`: a collection's cover "is a composite of its first four
/// member covers **unless the user sets a specific one**". ``CompositeCover`` has always
/// honoured the second half; nothing in either app ever let a reader reach it. This is the
/// reaching.
///
/// The composite is an option rather than an absence, because that is how a reader thinks
/// about it: a collection's cover is either "the four" or "that one", and a picker where
/// undoing a choice means finding a clear button is a picker that traps its own reader.
///
/// Android's `ShelfCoverChoice` answers these cases identically.
enum ShelfCoverChoice {
    /// One thing the picker offers.
    enum Option: Identifiable, Equatable, Hashable {
        /// The four member covers, which is what a collection wears until it is told
        /// otherwise.
        case composite
        /// One member's own cover, across the whole frame.
        case member(String)

        var id: String {
            switch self {
            case .composite: "composite"
            case let .member(member): member
            }
        }
    }

    /// Everything a reader may pick, in the order they are offered.
    ///
    /// The composite leads, always: it is the collection's own default and the way back from
    /// a choice already made. The members follow in identity order — the same order
    /// ``CompositeCover`` reads them in, so "the first four" on the composite tile are
    /// visibly the first four of the row underneath it. The library's own order was the
    /// tempting alternative and moves the moment the reader touches the sort control, which
    /// ``CompositeCover`` refused for the same reason.
    static func options(of collection: PublicationCollection) -> [Option] {
        [.composite] + collection.members.sorted().map(Option.member)
    }

    /// Which option the collection is wearing now.
    ///
    /// ``CompositeCover``'s rule, word for word: the reader's choice wins, and a cover that
    /// has left the collection is not the collection's cover any more. Answering it here
    /// from the same premise rather than from a stored flag is what keeps the tick in the
    /// picker and the artwork on the shelf from ever disagreeing.
    static func chosen(in collection: PublicationCollection) -> Option {
        guard let member = collection.coverMemberID, collection.members.contains(member) else {
            return .composite
        }
        return .member(member)
    }
}

/// Choosing a collection's cover.
///
/// A wall of the artwork itself rather than a list of titles, because the artwork is the
/// interface and this is the one screen in the app where the reader is being asked a
/// question *about* artwork. Tapping answers it and leaves: there is no second confirmation
/// for a change that shows itself immediately and is undone by tapping the next one.
struct ShelfCoverPicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: LibraryModel
    let collection: PublicationCollection

    /// Narrower than the shelf lattice: these are single covers rather than composites of
    /// four, so they stay legible small, and a collection of forty is a wall to scan rather
    /// than a list to page through.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: StoryArcSpace.md, alignment: .top)]
    }

    /// The collection as it would look with no choice made, for the composite's own tile.
    ///
    /// Without this the composite would preview the very cover the reader is trying to move
    /// away from — ``CompositeCover`` answers the chosen one when there is one, which is
    /// right everywhere except on the control that offers to unchoose it.
    private var unchosen: PublicationCollection {
        var copy = collection
        copy.coverMemberID = nil
        return copy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.md) {
                    Text("shelves.cover.about", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: StoryArcSpace.lg) {
                        ForEach(ShelfCoverChoice.options(of: collection)) { option in
                            cell(option)
                        }
                    }
                }
                .padding(StoryArcSpace.gutter)
            }
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("shelves.cover", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("shelves.cancel", bundle: .module) }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ option: ShelfCoverChoice.Option) -> some View {
        let publication = publication(for: option)
        let isChosen = ShelfCoverChoice.chosen(in: collection) == option
        // A member whose file has gone still counts as a member — `collections-and-reading-
        // lists` keeps an entry the source dropped rather than renumbering around it — but
        // there is no artwork to put on a shelf, so it is shown and not offered.
        let isPickable = option == .composite || publication != nil

        Button {
            choose(option)
        } label: {
            VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                ShelfCover(model: model, tiles: tiles(for: option), width: 140)
                    .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                            .strokeBorder(
                                isChosen ? theme.palette.accent : theme.palette.borderSubtle,
                                lineWidth: isChosen ? 3 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isChosen {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.palette.accent)
                                .padding(StoryArcSpace.xs)
                        }
                    }

                Text(caption(for: option, publication: publication))
                    .textRole(.caption)
                    .foregroundStyle(
                        isPickable ? theme.palette.textSecondary : theme.palette.textTertiary
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isPickable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// What the tile draws for an option. One cover for a member; the four for the composite.
    private func tiles(for option: ShelfCoverChoice.Option) -> [String] {
        switch option {
        case .composite: CompositeCover.tiles(of: unchosen)
        case let .member(member): [member]
        }
    }

    private func publication(for option: ShelfCoverChoice.Option) -> Publication? {
        guard case let .member(member) = option else { return nil }
        return model.publications.first { $0.id == member }
    }

    private func caption(
        for option: ShelfCoverChoice.Option,
        publication: Publication?
    ) -> String {
        switch option {
        case .composite:
            String(localized: "shelves.cover.composite", bundle: .module, locale: .storyArc)
        case .member:
            publication?.displayTitle
                ?? String(localized: "shelves.list.unavailable", bundle: .module, locale: .storyArc)
        }
    }

    private func choose(_ option: ShelfCoverChoice.Option) {
        switch option {
        case .composite: model.setCover(nil, onCollection: collection.id)
        case let .member(member): model.setCover(member, onCollection: collection.id)
        }
        dismiss()
    }
}
