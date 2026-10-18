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

    /// How far the grid's width moves at a time.
    static let widthStep: CGFloat = 24

    /// The width the grid is laid out at: the room it has, rounded down to ``widthStep``. A live resize proposed a new
    /// width every frame, and the lazy grid measured its rows again each time (19 frames a second at 5,000
    /// publications, `desktop-budgets-macos.md`); between two steps the grid is handed the same width and keeps its
    /// layout.
    static func snapped(_ width: CGFloat) -> CGFloat {
        max(0, (width / widthStep).rounded(.down) * widthStep)
    }

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
    @State private var memo = ShelfLayoutMemo()

    var body: some View {
        let sort = library.model.query.sort
        let shelf = memo.shelf(publications, sort: sort, divides: divides)
        GeometryReader { geometry in
            let rail = shelf.index.isEmpty ? 0 : ShelfIndexRail.width
            let width = LibraryGrid.snapped(geometry.size.width - rail)
            let columns = LibraryGrid.columns(for: width)
            ScrollViewReader { proxy in
                ScrollView {
                    content(columns: columns, order: shelf.ids, sort: sort)
                        .frame(width: width)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, shelf.index.isEmpty ? 0 : ShelfIndexRail.width)
                }
                .overlay(alignment: .trailing) {
                    if !shelf.index.isEmpty {
                        ShelfIndexRail(entries: shelf.index) { proxy.scrollTo($0.publicationID, anchor: .top) }
                    }
                }
            }
        }
        .onChange(of: shelf.ids) { _, ids in selection = selection.kept(in: ids) }
        .accessibilityLabel(Text("desktop.nav.library"))
    }

    /// One lazy grid for the whole shelf, its sections included: a grid per section inside a
    /// stack laid every cell of a section out when the section came into view.
    private func content(columns: [GridItem], order: [String], sort: LibrarySort) -> some View {
        let sections = groupSeries
            ? [] : memo.sections(publications, sort: sort, divides: divides, columns: columns.count)
        return LazyVGrid(columns: columns, spacing: LibraryGrid.spacing, pinnedViews: [.sectionHeaders]) {
            if groupSeries {
                ForEach(LibraryGrid.groupedBySeries(publications)) { group in
                    Section {
                        cells(group.publications, order: order)
                    } header: {
                        ShelfSectionHeading(title: group.name)
                    }
                }
            } else if !sections.isEmpty {
                ForEach(sections) { section in
                    Section {
                        cells(section.publications, order: order)
                    } header: {
                        ShelfSectionHeading(title: section.title)
                    }
                }
            } else {
                cells(publications, order: order)
            }
        }
        .padding(LibraryGrid.spacing)
    }

    private func cells(_ shown: [Publication], order: [String]) -> some View {
        ForEach(shown) { publication in
            CoverCell(library: library, publication: publication, isSelected: selection.contains(publication.id))
                .modifier(SelectionClicks(
                    id: publication.id, order: order, selection: $selection,
                    onOpen: { onOpen(publication) }
                ))
                .contextMenu {
                    PublicationMenu(
                        library: library, publication: publication, onOpen: onOpen, onShow: onShow,
                        selectionCount: RestartRequest.menuCount(for: publication.id, in: selection),
                        selected: selection.ids
                    )
                }
                .id(publication.id)
        }
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
