public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The compact list.
///
/// `library-browsing` requires a list beside the grid: past a certain size a
/// library is scanned by title rather than recognised by artwork, and a screen of
/// covers holds nine rows where a list holds twenty.
///
/// The same cells' worth of information, laid out for reading rather than for
/// looking: a small cover, the title, what distinguishes it, and how far in the
/// reader got.
struct CoverList: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publications: [Publication]
    /// Search results under their own headings. Empty means there is no search running and
    /// the list is one run of rows.
    var groups: [MatchGroup] = []
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    private let thumbnailWidth: CGFloat = 44

    var body: some View {
        List {
            // `library-browsing`: results are "grouped by match kind" while a search is
            // running. A list already has section headers, so grouping here costs the
            // reader nothing to learn.
            if groups.isEmpty {
                ForEach(publications) { row($0) }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.publications) { row($0) }
                    } header: {
                        Text(group.kind.titleKey, bundle: .module)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ publication: Publication) -> some View {
        ListRow(
            publication: publication,
            model: model,
            onOpen: onOpen,
            thumbnailWidth: thumbnailWidth,
            maxPixelSize: Int(thumbnailWidth * displayScale)
        )
        .listRowBackground(theme.palette.surfaceCanvas)
    }
}

struct ListRow: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let onOpen: (Publication) -> Void
    let thumbnailWidth: CGFloat
    let maxPixelSize: Int

    @State private var cover: CGImage?

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            thumbnail
                .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)
                .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(publication.displayTitle)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let fraction = model.readFraction(of: publication) {
                // A number here rather than a bar: a list row is read, and "48%"
                // is quicker to read than a sliver of colour is to measure.
                Text("library.cell.progress \(Int(fraction * 100))", bundle: .module)
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .contentShape(.rect)
        .onTapGesture { if publication.isOpenable { onOpen(publication) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(publication.isOpenable ? .isButton : [])
        .task(id: publication.id) {
            if cover == nil {
                cover = await model.cover(for: publication, maxPixelSize: maxPixelSize)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cover {
            Image(decorative: cover, scale: 1).resizable().scaledToFill()
        } else {
            theme.palette.surfaceRaised
        }
    }

    /// What distinguishes this row from its neighbours, format included: in a list
    /// the artwork is too small to say what kind of publication this is.
    ///
    /// The source is last and only sometimes there. `library-browsing`: a publication
    /// "shows its source only when more than one source is configured" — with one source
    /// the word would be on every row and would separate nothing from nothing.
    private var subtitle: String {
        var parts: [String] = []
        if !publication.isOpenable {
            parts.append(String(localized: "library.cell.cannotOpen", bundle: .module, locale: .storyArc))
        }
        if let series = publication.series, series != publication.displayTitle {
            parts.append(publication.number.map { "\(series) #\($0)" } ?? series)
        } else if let author = publication.authors.first {
            parts.append(author)
        }
        parts.append(publication.format.displayName)
        if let source = model.sourceName(of: publication) {
            parts.append(
                String(
                    localized: "library.cell.source \(source)",
                    bundle: .module,
                    locale: .storyArc
                )
            )
        }
        return parts.joined(separator: " · ")
    }
}
