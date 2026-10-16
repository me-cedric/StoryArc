import LibraryFeature
import StoryArcCore
import SwiftUI

/// The toolbar's trailing items: the view menu (grid or list, sort, filter).
///
/// `docs/designs/desktop/macos.md` section 3: "the view menu (grid or list, cover size,
/// sort, filter) and the search field. Nothing else." Cover size is wave 5's polish. The
/// query the menus edit is the shared `LibraryQuery`, through `LibraryMenus`. Task 2.23b.
struct LibraryToolbarMenus: ToolbarContent {
    let model: LibraryModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker(selection: layout) {
                Label("desktop.menu.viewGrid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                Label("desktop.menu.viewList", systemImage: "list.bullet").tag(LibraryLayout.list)
            } label: {
                Text("desktop.toolbar.view")
            }
            .pickerStyle(.segmented)
            .help(Text("desktop.toolbar.view"))

            Menu {
                ForEach(LibraryMenus.sorts, id: \.self) { sort in
                    Button { model.query = LibraryMenus.sorting(by: sort, in: model.query) } label: {
                        if model.query.sort == sort {
                            Label(sort.title, systemImage: model.query.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                Label("desktop.toolbar.sort", systemImage: "arrow.up.arrow.down")
            }
            .help(Text("desktop.toolbar.sort"))

            Menu {
                Section("desktop.filter.format") {
                    ForEach(model.availableFormats, id: \.self) { format in
                        Toggle(format.displayName, isOn: Binding(
                            get: { model.query.formats.contains(format) },
                            set: { _ in model.query = LibraryMenus.toggling(format, in: model.query) }
                        ))
                    }
                }
                Section("desktop.filter.readState") {
                    ForEach(LibraryMenus.readStates, id: \.self) { state in
                        Toggle(state.title, isOn: Binding(
                            get: { model.query.readStates.contains(state) },
                            set: { _ in model.query = LibraryMenus.toggling(state, in: model.query) }
                        ))
                    }
                }
                if model.registry.sources.count > 1 {
                    Section("desktop.filter.source") {
                        Picker(selection: Binding(
                            get: { model.query.scope },
                            set: { model.query = LibraryMenus.scoping($0, in: model.query) }
                        )) {
                            Text("desktop.filter.allSources").tag(LibraryScope.allSources)
                            ForEach(model.registry.sources) { source in
                                Text(source.displayName).tag(LibraryScope.source(source.id))
                            }
                        } label: { EmptyView() }
                        .pickerStyle(.inline)
                    }
                }
                if model.query.hasFilters {
                    Divider()
                    Button { model.clearFilters() } label: { Text("desktop.library.filtered.clear") }
                }
            } label: {
                Label("desktop.toolbar.filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help(Text("desktop.toolbar.filter"))
            .badge(model.query.activeFilterCount)
        }
    }

    private var layout: Binding<LibraryLayout> {
        Binding(get: { model.layout }, set: { model.layout = $0 })
    }
}

extension LibrarySort {
    var title: LocalizedStringKey {
        switch self {
        case .title: "desktop.sort.title"
        case .series: "desktop.sort.series"
        case .lastRead: "desktop.sort.lastRead"
        case .progress: "desktop.sort.progress"
        case .year: "desktop.sort.year"
        case .dateAdded: "desktop.sort.dateAdded"
        case .fileSize: "desktop.sort.fileSize"
        }
    }
}

extension ReadState {
    var title: LocalizedStringKey {
        switch self {
        case .unread: "desktop.filter.unread"
        case .inProgress: "desktop.filter.inProgress"
        case .finished: "desktop.filter.finished"
        }
    }
}
