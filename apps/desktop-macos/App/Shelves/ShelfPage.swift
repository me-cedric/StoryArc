import DesignSystem
import Persistence
import StoryArcCore
import SwiftUI

/// A shelf's page in the content column: a collection as a cover grid, a reading list as its
/// numbered entries in the reader's order.
///
/// `collections-and-reading-lists`. A list's entries move by drag and leave by their menu; an
/// entry whose publication is gone keeps its place, unavailable; an edit still owed to its
/// server is drawn grey. An empty shelf says how to fill it.
struct ShelfPage: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let pin: ShelfPin
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        Group {
            if let row = library.shelfRows.first(where: { $0.pin == pin }) {
                content(row)
                    .toolbar {
                        ToolbarItem {
                            Menu { ShelfRowMenu(library: library, row: row) } label: {
                                Label("desktop.shelves.actions \(row.name)", systemImage: "ellipsis.circle")
                            }
                        }
                    }
            } else {
                ContentUnavailableView("desktop.shelves.gone", systemImage: "square.stack")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.surfaceCanvas)
    }

    @ViewBuilder
    private func content(_ row: ShelfRow) -> some View {
        if row.isEmpty {
            ContentUnavailableView {
                Label(row.name, systemImage: row.symbolName)
            } description: {
                Text("desktop.shelves.empty")
            }
        } else {
            switch pin {
            case let .list(id):
                list(id)
            default:
                CoverGridView(
                    library: library,
                    publications: MacShelves.members(
                        of: pin, in: library.model.shelves, library: library.model.publications
                    ),
                    groupSeries: false, selection: $selection, onOpen: onOpen, onShow: onShow
                )
            }
        }
    }

    private func list(_ id: UUID) -> some View {
        let entries = MacShelves.entries(
            of: id, in: library.model.shelves, library: library.model.publications, pending: []
        )
        return List {
            ForEach(entries) { entry in
                ShelfEntryRow(library: library, entry: entry, onOpen: onOpen) {
                    Task { await library.remove(entry.id, from: pin) }
                }
            }
            .onMove { from, to in
                guard let first = from.first, entries.indices.contains(first) else { return }
                library.move(entries[first].id, to: to > first ? to - 1 : to, inList: id)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// One numbered entry of a reading list: its title, its read state, grey when pending or gone.
private struct ShelfEntryRow: View {
    let library: MacLibrary
    let entry: ShelfListEntry
    let onOpen: (Publication) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(entry.position).").monospacedDigit().foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).foregroundStyle(entry.publication == nil ? .secondary : .primary)
                if entry.isPending {
                    Text("desktop.shelves.pending").scaledFont(.caption).foregroundStyle(.secondary)
                } else if entry.publication == nil {
                    Text("desktop.shelves.unavailable").scaledFont(.caption).foregroundStyle(.secondary)
                } else if let publication = entry.publication,
                          let fraction = library.model.readFraction(of: publication) {
                    Text("desktop.cover.percentRead \(Int(fraction * 100))")
                        .scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let publication = entry.publication { onOpen(publication) } }
        .contextMenu {
            if let publication = entry.publication {
                Button { onOpen(publication) } label: { Text("desktop.menu.read") }
                Divider()
            }
            Button(role: .destructive, action: onRemove) { Text("desktop.shelves.removeFromList") }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The shelves on Home: collections, then reading lists, pinned first, each absent when empty.
struct HomeShelvesSection: View {
    let library: MacLibrary
    let onShelf: (ShelfPin) -> Void

    var body: some View {
        let home = MacShelves.home(library.model.shelves, pins: ShelfPins.shared.pins)
        if !home.collections.isEmpty { row("desktop.shelves.collections", home.collections) }
        if !home.lists.isEmpty { row("desktop.shelves.lists", home.lists) }
    }

    private func row(_ title: LocalizedStringKey, _ shelves: [ShelfRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).scaledFont(.title2, weight: .semibold).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(shelves) { shelf in
                        Button { onShelf(shelf.pin) } label: { ShelfCard(library: library, shelf: shelf) }
                            .buttonStyle(.plain)
                            // On the button itself, so VoiceOver and the audit read one named button.
                            .accessibilityLabel(ShelfCard.label(of: shelf, in: library))
                            .contextMenu { ShelfRowMenu(library: library, row: shelf) }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// A shelf on Home: the first member's cover, or the well, and the shelf's name and count.
private struct ShelfCard: View {
    @Environment(\.theme) private var theme
    let library: MacLibrary
    let shelf: ShelfRow

    var body: some View {
        let first = MacShelves.members(
            of: shelf.pin, in: library.model.shelves, library: library.model.publications
        ).first
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let first {
                    CoverImage(library: library, publication: first, maxPixelSize: 300)
                } else {
                    Image(systemName: shelf.symbolName).font(.largeTitle).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.palette.surfaceSunken)
                }
            }
            .frame(width: 110, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(shelf.name).scaledFont(.callout, weight: .medium).lineLimit(1)
            if let read {
                Text("desktop.shelves.listRead \(read) \(shelf.count)").scaledFont(.caption).foregroundStyle(.secondary)
            } else {
                Text("desktop.shelves.count \(shelf.count)").scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 110, alignment: .leading)
    }

    private var read: Int? { Self.read(of: shelf, in: library) }

    /// A reading list's entries read so far; nil for a collection, which has no position.
    static func read(of shelf: ShelfRow, in library: MacLibrary) -> Int? {
        guard case let .list(id) = shelf.pin else { return nil }
        let all = Set(library.model.publications.map(\.id))
        return MacShelves.readThrough(id, in: library.model.shelves, finished: library.finished(among: all))
    }

    /// What VoiceOver reads for the card: its name, how much is on it, and a list's progress.
    static func label(of shelf: ShelfRow, in library: MacLibrary) -> Text {
        if let read = read(of: shelf, in: library) {
            return Text("desktop.shelves.listCard \(shelf.name) \(read) \(shelf.count)")
        }
        return Text("desktop.shelves.card \(shelf.name) \(shelf.count)")
    }
}
