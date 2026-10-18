import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// A source's own screen (`sources`, *A refresh of one source from its own screen*; `opds-catalog`, *Browsing a
/// navigation feed*, *Grouped feed*, *Facets*, *Search*; `kavita-server`, *Browsing a Kavita source*, *Searching a
/// Kavita source*): the phones' `SourceBrowser` in a window of its own, with Refresh and Rename in its toolbar. A
/// publication opened from it reads in a reader window like any other.
struct SourceWindow: View {
    static let id = "source"

    let library: MacLibrary
    let sourceID: UUID
    @Environment(\.openWindow) private var openWindow
    @State private var isRenaming = false
    @State private var name = ""

    private var source: Source? { library.model.registry.sources.first { $0.id == sourceID } }

    var body: some View {
        if let source {
            NavigationStack {
                SourceBrowser(source: source, model: library.model, onOpen: open) {
                    await library.servers.refresh(sourceID)
                }
            }
            .navigationTitle(source.displayName)
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await library.servers.refresh(sourceID) } } label: {
                        Label("desktop.sources.refresh", systemImage: "arrow.clockwise")
                    }
                    Button { name = source.displayName; isRenaming = true } label: {
                        Label("desktop.sources.rename", systemImage: "pencil")
                    }
                }
            }
            .sheet(isPresented: $isRenaming) {
                SourceRenameSheet(name: $name) { library.model.rename(source, to: $0) }
            }
            .frame(minWidth: 640, minHeight: 480)
        } else {
            ContentUnavailableView("desktop.source.gone", systemImage: "questionmark.folder")
        }
    }

    private func open(_ publication: Publication, _ url: URL) {
        openWindow.reader(ReaderTarget(
            publicationID: publication.id, path: url.path(percentEncoded: false), title: publication.displayTitle
        ))
    }
}

/// A new name for a source; an empty one changes nothing (`sources`, *Renaming a source*).
struct SourceRenameSheet: View {
    @Binding var name: String
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("desktop.sources.rename.field", text: $name)
            HStack {
                Spacer()
                Button("desktop.sources.rename.cancel", role: .cancel) { dismiss() }
                Button("desktop.sources.rename.save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onRename(trimmed) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// Where a source moves to, in the registry's own terms (`sources`, *Reordering sources*): its destination is an
/// insertion index, as a list's move hands one over.
enum SourceOrder {
    static func up(from index: Int) -> Int? { index > 0 ? index - 1 : nil }

    static func down(from index: Int, count: Int) -> Int? { index < count - 1 ? index + 2 : nil }
}
