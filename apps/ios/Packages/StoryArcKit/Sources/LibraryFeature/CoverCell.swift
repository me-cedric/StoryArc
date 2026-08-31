internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// One publication in the grid.
//
// Split out of `CoverGrid.swift`, which had reached the 400-line cap this project enforces
// once search grouping and bulk selection both landed in it. The division is the one the
// file already made: the grid is a layout, the cell is a publication.

/// One publication in the grid.
struct CoverCell: View {
    /// The server whose list just refused this publication, if one did.
    @State private var refusedServer: String?
    @State private var restarting: Publication?

    @Environment(\.theme) private var theme
    /// How large the reader has asked for text to be. Read for the coverless well only —
    /// see ``coverlessWellDrawsTitle(at:)``; the column width is the grid's question.
    @Environment(\.dynamicTypeSize) private var textSize

    let publication: Publication
    let model: LibraryModel
    let maxPixelSize: Int

    /// Whether this one is picked, or `nil` when the library is not in selection mode.
    var isPicked: Bool?
    var onToggle: (Publication) -> Void = { _ in }

    @State private var cover: CGImage?
    @State private var didAttemptLoad = false

    /// The cell, and what a tap on it does.
    ///
    /// **A cover leads to the publication's page, not to the reader.** `publication-detail`
    /// makes that the rule for every cover on every surface, and separates it from resuming:
    /// a reader who chooses *Keep reading* has already decided, and that affordance still
    /// opens the book directly. This is the other verb — "what is this", not "carry on".
    ///
    /// A link rather than a callback, so the enclosing stack's single `PublicationRoute`
    /// registration does the work and this cell does not have to know what a publication's
    /// page is made of. It is also what gets the cell the system's own link behaviour, which
    /// a tap gesture never had.
    ///
    /// Two cases still do not navigate, and neither is new. While the reader is picking, a
    /// tap picks — opening a page mid-selection would throw away everything chosen so far.
    /// And a publication that cannot be read at all is not tappable: `publication-formats`
    /// requires a named refusal, the caption already carries it, and a page whose one action
    /// is unavailable is a second place to read the same refusal.
    var body: some View {
        Group {
            if isPicked == nil, publication.isOpenable {
                NavigationLink(value: PublicationRoute(publication)) { cell }
                    .buttonStyle(.plain)
            } else {
                cell
                    .contentShape(.rect)
                    .onTapGesture { if isPicked != nil { onToggle(publication) } }
            }
        }
        // `collections-and-reading-lists`: a publication "may belong to any number of
        // collections", and this is where a reader says so. Only shown when there is
        // somewhere to add it to — a menu whose only content is "you have no collections"
        // is a menu that wastes a long press. Absent while picking: the bar below is
        // already offering the same actions for everything that is picked.
        .contextMenu {
            if isPicked == nil {
                AddToShelfMenu(
                    model: model,
                    publications: [publication],
                    onRefused: { refusedServer = $0 },
                    onRestart: { restarting = publication }
                )
            }
        }
        // `reading-progress` requires the clear to be confirmed. Here rather than in the
        // menu because a context menu cannot present one, and destructive because it is:
        // the position is the only copy the app promises never to lose.
        .confirmationDialog(
            Text("library.restart.title \(publication.displayTitle)", bundle: .module),
            isPresented: Binding(
                get: { restarting?.id == publication.id },
                set: { if !$0 { restarting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await model.restart(publication) }
                restarting = nil
            } label: {
                Text("library.restart.confirm", bundle: .module)
            }
        } message: {
            Text("library.restart.body", bundle: .module)
        }
        .refusedByServer($refusedServer, model: model, publication: publication)
        // One label for the whole cell. Read as three separate elements it would
        // announce the title, then the format, then an unlabelled image.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(publication.isOpenable ? .isButton : [])
        // Spoken, because a tick in the corner of a cover is invisible to VoiceOver and
        // "is this one picked" is the only question selection mode asks.
        .accessibilityAddTraits(isPicked == true ? .isSelected : [])
        .task(id: publication.id) {
            guard !didAttemptLoad else { return }
            didAttemptLoad = true
            cover = await model.cover(for: publication, maxPixelSize: maxPixelSize)
        }
    }

    /// The artwork, its marks, and the caption under them.
    private var cell: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            artwork
                // 2:3 is the comic and book proportion. Fixing it here means a
                // cell reserves its space before its cover arrives, so the grid
                // does not reflow as images land.
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                // `design.md`: "Cover radius stays at 4 pt on purpose. A comic
                // cover is printed stock." `StoryArcRadius.cover` is that 4 pt,
                // and it had been defined and then used by nothing — the cell
                // rounded artwork to `md`, 10 pt, which is an app icon.
                .clipShape(.rect(cornerRadius: StoryArcRadius.cover))
                .overlay {
                    // A hairline rather than a shadow: a pale cover on a pale
                    // surface needs an edge, and a shadow under every cell reads
                    // as noise at grid density.
                    RoundedRectangle(cornerRadius: StoryArcRadius.cover)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    if let fraction = model.readFraction(of: publication) {
                        ProgressBar(fraction: fraction)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let isPicked { PickMark(isPicked: isPicked) }
                }
                // `design.md` asks for "downloaded state as a small filled mark in one
                // corner", and the palette calls `status/downloaded` "the one badge
                // permitted to compete with cover art". Neither platform drew it.
                //
                // Not while picking. `library-browsing` lets a cover carry "at most two
                // marks: how far the reader has got, and whether it can be read with no
                // network", and "no third mark is added to a cover for any reason" — so
                // the pick mark is not an addition to that pair, it is a substitution
                // into it. This one is what gives, because availability answers a
                // browsing question and the reader has stopped browsing: the only
                // question selection mode asks is which covers are picked. The progress
                // rail stays, because it is the rail along the artwork's foot rather
                // than a second glyph in the trailing corners, and because how far in a
                // cover is remains how a reader finds the ones they meant to pick.
                //
                // Spoken either way — see ``accessibilityLabel``. A mark withheld to keep
                // the artwork legible is not a fact withheld.
                .overlay(alignment: .bottomTrailing) {
                    if showsOnDeviceMark { OnDeviceMark() }
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(publication.displayTitle)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            // Letterboxed, not cropped. `design.md`: "Manga volumes and EPUB covers
            // vary. The cell crops to a consistent shape and letterboxes onto
            // `surfaceSunken` rather than distorting art." `.scaledToFill()` inside a
            // fixed 2:3 frame did the opposite — it cut the edges off every cover whose
            // proportion was not the comic trim, which is most of a manga shelf and
            // every square EPUB. The artwork is the interface; a well behind it is a
            // cheaper price than a crop through it.
            ZStack {
                theme.palette.surfaceSunken

                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            // A set title rather than an empty rectangle. A grid of publications with no
            // cover art — and plenty of EPUBs carry none — was a wall of identical grey
            // cards labelled with a format, which is the one thing every card in that wall
            // had in common. The title is what tells them apart. The format stays, smaller,
            // because it is still the answer to "why is there no picture".
            //
            // The title at the reader's own size, and gone once that size is one this well
            // cannot hold — never shrunk to fit. ``coverlessWellDrawsTitle(at:)`` carries
            // the whole argument, and the caption below this cell is what keeps the title
            // from being lost.
            ZStack(alignment: .bottom) {
                theme.palette.surfaceRaised

                if coverlessWellDrawsTitle(at: textSize) {
                    Text(publication.displayTitle)
                        .textRole(.headline)
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, StoryArcSpace.sm)
                        .frame(maxHeight: .infinity)
                }

                Text(publication.format.displayName)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .padding(.bottom, StoryArcSpace.xs)
            }
        }
    }

    /// Whether this cover carries the downloaded mark.
    ///
    /// A named rule rather than a condition inline in the body, because it *is* a rule:
    /// `library-browsing` caps a cover at two marks, and a view body is not somewhere a
    /// cap can be asserted. This is the assertable half of it.
    var showsOnDeviceMark: Bool {
        isPicked == nil && model.isOnDevice(publication)
    }

    /// The second line: what distinguishes this row from its neighbours.
    ///
    /// Internal rather than private so the fall-through can be asserted without a window:
    /// which of the two facts a cover states under its title is the substance of the
    /// caption, and a view body is not somewhere that can be checked.
    var subtitle: String? {
        if !publication.isOpenable {
            // Said plainly rather than shown as a broken cover. `publication-formats`
            // requires a named refusal, and a grid cell is where a user meets it.
            return String(localized: "library.cell.cannotOpen", bundle: .module, locale: .storyArc)
        }
        // The author when the series line would only repeat the title — the same
        // fall-through the no-series case has always taken.
        return seriesLine(for: publication) ?? publication.authors.first
    }

    private var accessibilityLabel: String {
        var parts = [publication.displayTitle]
        if let subtitle { parts.append(subtitle) }
        parts.append(publication.format.displayName)
        // Progress is spoken, because a bar at the foot of a cover is invisible to
        // anyone using VoiceOver and "how far in am I" is the whole point of it.
        if let fraction = model.readFraction(of: publication) {
            parts.append(
                String(
                    localized: "library.cell.progress \(Int(fraction * 100))",
                    bundle: .module
                )
            )
        }
        // Spoken for the same reason the progress is: a mark in the corner of a cover
        // is invisible to VoiceOver, and "can I read this on the train" is the whole
        // question the mark answers. The wording is the one the catalogue already uses
        // for the same state, in the four languages it is already translated into.
        if model.isOnDevice(publication) {
            parts.append(
                String(localized: "catalogue.entry.downloaded", bundle: .module, locale: .storyArc)
            )
        }
        if let pageCount = publication.pageCount {
            parts.append(String(localized: "library.cell.pages \(pageCount)", bundle: .module, locale: .storyArc))
        }
        // No source. `library-browsing`: "nothing on the shelf states which source a
        // publication came from" — and a fact removed from the artwork but left in the
        // spoken label is the same leak, read aloud. The publication's own page carries
        // the one provenance line, for every reader alike.
        return parts.joined(separator: ", ")
    }
}
