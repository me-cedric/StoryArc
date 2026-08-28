public import SwiftUI

internal import DesignSystem
public import Persistence
public import StoryArcCore

/// Collections and reading lists, in one place.
///
/// `collections-and-reading-lists` requires local and server groupings to appear "in one
/// list, each labelled with its source" rather than segregated. Two sections here because
/// they are two different ideas, not two different origins — the origin is a label on a row.
public struct ShelvesView: View {
    @Environment(\.theme) private var theme

    private let model: LibraryModel
    private let onOpen: (Publication, URL) -> Void

    @State private var creating: Kind?
    @State private var draftName = ""

    /// Which kind the "new" sheet is making.
    private enum Kind: String, Identifiable {
        case collection
        case list

        var id: String { rawValue }
    }

    public init(model: LibraryModel, onOpen: @escaping (Publication, URL) -> Void = { _, _ in }) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        let shelves = model.shelves

        List {
            Section {
                if shelves.collections.isEmpty {
                    Text("shelves.collections.none", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    ForEach(shelves.collections) { collection in
                        NavigationLink {
                            CollectionDetail(model: model, id: collection.id, onOpen: onOpen)
                        } label: {
                            row(
                                name: collection.name,
                                count: collection.members.count,
                                origin: collection.origin
                            )
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.delete(collection: shelves.collections[index].id)
                        }
                    }
                }
            } header: {
                Text("shelves.collections", bundle: .module)
            }

            Section {
                if shelves.lists.isEmpty {
                    Text("shelves.lists.none", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    ForEach(shelves.lists) { list in
                        NavigationLink {
                            ReadingListDetail(model: model, id: list.id, onOpen: onOpen)
                        } label: {
                            row(name: list.name, count: list.entries.count, origin: list.origin)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.delete(list: shelves.lists[index].id)
                        }
                    }
                }
            } header: {
                Text("shelves.lists", bundle: .module)
            }
        }
        .navigationTitle(Text("shelves.title", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        draftName = ""
                        creating = .collection
                    } label: {
                        Text("shelves.new.collection", bundle: .module)
                    }
                    Button {
                        draftName = ""
                        creating = .list
                    } label: {
                        Text("shelves.new.list", bundle: .module)
                    }
                } label: {
                    Label {
                        Text("shelves.new", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert(
            Text(creating == .list ? "shelves.new.list" : "shelves.new.collection", bundle: .module),
            isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } }),
            presenting: creating
        ) { kind in
            TextField(String(localized: "shelves.new.field", bundle: .module), text: $draftName)
            Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            Button {
                switch kind {
                case .collection: model.create(collection: draftName)
                case .list: model.create(list: draftName)
                }
            } label: {
                Text("shelves.create", bundle: .module)
            }
        } message: { _ in
            // `collections-and-reading-lists`: "the storage location is stated at creation,
            // not discovered later". There is one location today, and saying so is what
            // makes the sentence true rather than merely unfalsified.
            Text("shelves.new.storedLocally", bundle: .module)
        }
    }

    @ViewBuilder
    private func row(name: String, count: Int, origin: ShelfOrigin) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(name)
                .foregroundStyle(theme.palette.textPrimary)

            Text(subtitle(count: count, origin: origin))
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// The count, and where the grouping came from.
    private func subtitle(count: Int, origin: ShelfOrigin) -> String {
        let items = String(
            format: String(localized: "shelves.count \(count)", bundle: .module),
            count
        )
        guard let sourceID = origin.sourceID,
              let source = model.registry[sourceID]
        else {
            return items
        }
        return "\(source.displayName) · \(items)"
    }
}
