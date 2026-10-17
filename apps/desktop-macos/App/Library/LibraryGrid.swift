import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// A series on the shelf when the sidebar groups by series.
struct SeriesGroup: Identifiable, Equatable {
    let name: String
    let publications: [Publication]

    var id: String { name }
}

/// The grid's arithmetic, pure so `LibraryViewModelTests` holds it.
enum LibraryGrid {
    static let cellWidth: CGFloat = 150
    static let spacing: CGFloat = 20

    /// Columns for a width: as many cells as fit, never fewer than two.
    static func columns(for width: CGFloat) -> [GridItem] {
        guard width > 0 else { return [] }
        let count = max(2, Int((width - spacing) / (cellWidth + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// One group per series in first-seen order; a publication with none is its own group.
    static func groupedBySeries(_ publications: [Publication]) -> [SeriesGroup] {
        var order: [String] = []
        var members: [String: [Publication]] = [:]
        for publication in publications {
            let name = publication.series ?? publication.displayTitle
            if members[name] == nil { order.append(name) }
            members[name, default: []].append(publication)
        }
        return order.map { SeriesGroup(name: $0, publications: members[$0] ?? []) }
    }
}

/// The cover grid, with the cover ladder in every cell.
///
/// A long shelf is divided by the active sort with headings that stay pinned while their
/// section is on screen, and sorted by title or series it carries the index down its
/// trailing edge (`ShelfSections`). Neither is drawn over a search's results or over the
/// sidebar's series grouping, which are already grouped.
struct CoverGridView: View {
    let library: MacLibrary
    let publications: [Publication]
    let groupSeries: Bool
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void
    /// Whether the shelf may be divided and indexed.
    var divides = false

    var body: some View {
        let index = divides
            ? ShelfSections.index(publications, sort: library.model.query.sort, locale: .storyArc) : []
        GeometryReader { geometry in
            let columns = LibraryGrid.columns(for: geometry.size.width - (index.isEmpty ? 0 : ShelfIndexRail.width))
            ScrollViewReader { proxy in
                ScrollView {
                    content(columns: columns)
                        .padding(.trailing, index.isEmpty ? 0 : ShelfIndexRail.width)
                }
                .overlay(alignment: .trailing) {
                    if !index.isEmpty {
                        ShelfIndexRail(entries: index) { proxy.scrollTo($0.publicationID, anchor: .top) }
                    }
                }
            }
        }
        .onChange(of: publications.map(\.id)) { _, ids in selection = selection.kept(in: ids) }
        .accessibilityLabel(Text("desktop.nav.library"))
    }

    @ViewBuilder
    private func content(columns: [GridItem]) -> some View {
        let sections = divides ? ShelfSections.divide(
            publications, by: library.model.query.sort, columns: columns.count, locale: .storyArc
        ) : []
        if groupSeries {
            ForEach(LibraryGrid.groupedBySeries(publications)) { group in
                Section {
                    grid(group.publications, columns: columns)
                } header: {
                    ShelfSectionHeading(title: group.name)
                }
            }
        } else if !sections.isEmpty {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        grid(section.publications, columns: columns)
                    } header: {
                        ShelfSectionHeading(title: section.title)
                    }
                }
            }
        } else {
            grid(publications, columns: columns)
        }
    }

    private func grid(_ shown: [Publication], columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: LibraryGrid.spacing) {
            ForEach(shown) { publication in
                CoverCell(library: library, publication: publication, isSelected: selection.contains(publication.id))
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
                    .id(publication.id)
            }
        }
        .padding(LibraryGrid.spacing)
    }
}

/// A section's heading, opaque so the covers scroll under it while it is pinned.
struct ShelfSectionHeading: View {
    @Environment(\.theme) private var theme

    let title: String

    var body: some View {
        Text(title).scaledFont(.title3, weight: .semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LibraryGrid.spacing)
            .padding(.vertical, 6)
            .background(theme.palette.surfaceCanvas)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A click selects, Command-click toggles, Shift-click extends, a double click opens.
struct SelectionClicks: ViewModifier {
    let id: String
    let order: [String]
    @Binding var selection: LibrarySelection
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .gesture(TapGesture(count: 2).onEnded { onOpen() })
            .gesture(TapGesture().modifiers(.command).onEnded { selection = selection.commandClicked(id) })
            .gesture(TapGesture().modifiers(.shift).onEnded { selection = selection.shiftClicked(id, order: order) })
            .gesture(TapGesture().onEnded { selection = selection.clicked(id) })
    }
}
