import LibraryFeature
import StoryArcCore
import SwiftUI

/// Sources: the folders and the servers, each with its state, and one way to add each kind.
///
/// `docs/designs/desktop/macos.md` section 5: a list with a state, offline sources dimmed,
/// add and remove under the list, and removing asks first and says downloads and progress
/// stay. A row's own actions are one menu (`AGENTS.md` section 6), the destructive one last.
struct SourcesSettingsTab: View {
    let library: MacLibrary

    @State private var removing: SourceRow?
    @State private var removingFolder: FolderSource?

    var body: some View {
        Group {
            list
            addSection
        }
        .addingSources(library.servers)
        .confirmationDialog(
            Text("desktop.sources.remove.title \(removing?.name ?? "")"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let removing { library.servers.remove(removing.id) }
                removing = nil
            } label: { Text("desktop.sources.remove") }
        } message: {
            Text("desktop.sources.remove.body")
        }
        .confirmationDialog(
            Text("desktop.sources.remove.title \(removingFolder?.name ?? "")"),
            isPresented: Binding(get: { removingFolder != nil }, set: { if !$0 { removingFolder = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let removingFolder { library.removeFolder(removingFolder) }
                removingFolder = nil
            } label: { Text("desktop.sources.remove") }
        } message: {
            Text("desktop.sources.remove.body")
        }
    }

    private var list: some View {
        Section {
            if library.sources.isEmpty, library.servers.rows.isEmpty {
                Text("desktop.settings.sources.none").foregroundStyle(.secondary)
            }
            ForEach(library.sources) { folder in
                folderRow(folder)
            }
            ForEach(library.servers.rows) { row in
                serverRow(row)
            }
        } header: {
            Text("desktop.settings.sources.list")
        } footer: {
            Text("desktop.settings.sources.footer").foregroundStyle(.secondary)
        }
    }

    private var addSection: some View {
        Section {
            Menu {
                Button { library.chooseFolder() } label: { Label("desktop.sources.add.folder", systemImage: "folder") }
                Button { library.servers.adding = .share } label: {
                    Label("desktop.sources.add.share", systemImage: SourceRow.Kind.share.symbolName)
                }
                Button { library.servers.adding = .catalogue } label: {
                    Label("desktop.sources.add.catalogue", systemImage: SourceRow.Kind.catalogue.symbolName)
                }
                Button { library.servers.adding = .kavita } label: {
                    Label("desktop.sources.add.kavita", systemImage: SourceRow.Kind.kavita.symbolName)
                }
            } label: {
                Text("desktop.sources.add")
            }
            .fixedSize()
        }
    }

    private func folderRow(_ source: FolderSource) -> some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(source.isGrey ? .secondary : .primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(source.name).foregroundStyle(source.isGrey ? .secondary : .primary)
                if source.state == .offline {
                    Text("desktop.settings.sources.offline").scaledFont(.caption).foregroundStyle(.secondary)
                } else if source.state == .needsAccess {
                    Text("desktop.settings.sources.needsAccess").scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if source.state == .needsAccess {
                    Button { library.repick(source) } label: { Text("desktop.source.chooseAgain") }
                    Divider()
                }
                Button(role: .destructive) { removingFolder = source } label: { Text("desktop.sources.remove.menu") }
            } label: {
                Label("desktop.sources.actions \(source.name)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .rowMenu()
        }
    }

    private func serverRow(_ row: SourceRow) -> some View {
        HStack {
            Image(systemName: row.kind.symbolName).foregroundStyle(row.isGrey ? .secondary : .primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(row.name).foregroundStyle(row.isGrey ? .secondary : .primary)
                Text(verbatim: row.address).scaledFont(.caption).foregroundStyle(.secondary)
                ForEach(Array(row.lines.enumerated()), id: \.offset) { _, line in
                    line.text.scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button { Task { await library.servers.refresh(row.id) } } label: { Text("desktop.sources.refresh") }
                if row.offersReconnect {
                    Button { library.servers.reconnect(row.id) } label: { Text("desktop.sources.reconnect") }
                }
                Divider()
                Button(role: .destructive) { removing = row } label: { Text("desktop.sources.remove.menu") }
            } label: {
                Label("desktop.sources.actions \(row.name)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .rowMenu()
        }
    }
}
