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
struct CoverGridView: View {
    let library: MacLibrary
    let publications: [Publication]
    let groupSeries: Bool
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if groupSeries {
                    ForEach(LibraryGrid.groupedBySeries(publications)) { group in
                        Section {
                            grid(group.publications, width: geometry.size.width)
                        } header: {
                            Text(group.name).scaledFont(.title3, weight: .semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, LibraryGrid.spacing)
                        }
                    }
                } else {
                    grid(publications, width: geometry.size.width)
                }
            }
        }
        .onChange(of: publications.map(\.id)) { _, ids in selection = selection.kept(in: ids) }
        .accessibilityLabel(Text("desktop.nav.library"))
    }

    private func grid(_ shown: [Publication], width: CGFloat) -> some View {
        LazyVGrid(columns: LibraryGrid.columns(for: width), spacing: LibraryGrid.spacing) {
            ForEach(shown) { publication in
                CoverCell(library: library, publication: publication, isSelected: selection.contains(publication.id))
                    .modifier(SelectionClicks(
                        id: publication.id, order: shown.map(\.id), selection: $selection,
                        onOpen: { onOpen(publication) }
                    ))
                    .contextMenu {
                        PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: onShow)
                    }
            }
        }
        .padding(LibraryGrid.spacing)
    }
}

/// The compact list, for a library too large to recognise by artwork alone.
struct CoverListView: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publications: [Publication]
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        List(publications) { publication in
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
            .contextMenu { PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: onShow) }
            .accessibilityLabel(Text(
                CoverCell.label(for: publication, fraction: library.model.readFraction(of: publication))
            ))
        }
        .scrollContentBackground(.hidden)
    }

    /// The series line the grid shows, then the format; never the title again.
    private func subtitle(of publication: Publication) -> String {
        [CoverCell.secondLine(of: publication), publication.format.displayName]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// A click selects, Command-click toggles, Shift-click extends, a double click opens.
private struct SelectionClicks: ViewModifier {
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
