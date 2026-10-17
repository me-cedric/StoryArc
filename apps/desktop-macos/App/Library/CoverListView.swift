import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// The compact list, for a library too large to recognise by artwork alone.
///
/// Divided and indexed as the grid is, at one column, so a heading costs one row.
struct CoverListView: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publications: [Publication]
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void
    /// Whether the shelf may be divided and indexed.
    var divides = false

    var body: some View {
        let sort = library.model.query.sort
        let sections = divides ? ShelfSections.divide(publications, by: sort, columns: 1, locale: .storyArc) : []
        let index = divides ? ShelfSections.index(publications, sort: sort, locale: .storyArc) : []
        ScrollViewReader { proxy in
            List {
                if sections.isEmpty {
                    ForEach(publications) { row($0) }
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.publications) { row($0) }
                        } header: {
                            Text(section.title).scaledFont(.headline).accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaPadding(.trailing, index.isEmpty ? 0 : ShelfIndexRail.width)
            .overlay(alignment: .trailing) {
                if !index.isEmpty {
                    ShelfIndexRail(entries: index) { proxy.scrollTo($0.publicationID, anchor: .top) }
                }
            }
        }
    }

    private func row(_ publication: Publication) -> some View {
        HStack(spacing: 12) {
            CoverImage(library: library, publication: publication, maxPixelSize: 120)
                .frame(width: 36, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(publication.displayTitle).scaledFont(.body).lineLimit(1)
                Text(subtitle(of: publication)).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let fraction = library.model.readFraction(of: publication) {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(selection.contains(publication.id) ? theme.palette.surfaceRaised : Color.clear)
        .modifier(SelectionClicks(
            id: publication.id, order: publications.map(\.id), selection: $selection,
            onOpen: { onOpen(publication) }
        ))
        .contextMenu {
            PublicationMenu(
                library: library, publication: publication, onOpen: onOpen, onShow: onShow,
                selectionCount: RestartRequest.menuCount(for: publication.id, in: selection)
            )
        }
        .accessibilityLabel(Text(
            CoverCell.label(for: publication, fraction: library.model.readFraction(of: publication))
        ))
        .id(publication.id)
    }

    /// The series line the grid shows, then the format; never the title again.
    private func subtitle(of publication: Publication) -> String {
        [CoverCell.secondLine(of: publication), publication.format.displayName]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
