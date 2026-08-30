internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Where the sidebar can send a reader.
///
/// `native-experience`: a window with room for it "uses a multi-column layout with a
/// persistent sidebar, not a stretched phone layout". These are exactly the places a
/// narrow window reaches through the catalogue strip and the right-hand toolbar buttons.
/// The wide window shows them all at once instead of keeping two of them behind chrome —
/// nothing new to learn, just nothing hidden.
enum SidebarDestination: Hashable, Identifiable {
    /// Everything already on the device.
    case library
    /// One catalogue, server or share, browsed rather than scanned.
    case source(Source.ID)
    /// Collections and reading lists.
    case shelves

    var id: Self { self }

    /// What a sidebar holds, in the order a reader meets it.
    ///
    /// A pure function of the registry, and the only place that order is decided, so the
    /// list can be asserted without building a view — which matters here because there
    /// is no simulator in this loop. Android's `sidebarDestinations` returns the same
    /// three groups in the same order.
    ///
    /// A local folder is deliberately absent: its publications were scanned into the
    /// grid, so a row for it would lead back to the row above it.
    static func all(for sources: [Source]) -> [SidebarDestination] {
        [.library]
            + sources.filter { $0.kind.isBrowsable }.map { SidebarDestination.source($0.id) }
            + [.shelves]
    }
}

/// The persistent sidebar of a wide window.
///
/// A `List` with the system's own sidebar style rather than a hand-built column:
/// `native-experience` says the platform's control is used wherever it exists, and this
/// is the control — it brings the selection highlight, the collapse behaviour and the
/// keyboard focus ring that a stack of buttons would each have to be given by hand.
struct LibrarySidebar: View {
    @Environment(\.theme) private var theme

    let sources: [Source]
    /// Optional because that is the shape `List` takes on iOS: a sidebar with
    /// nothing selected is a real state there, and the detail column falls back to the
    /// library when it happens.
    @Binding var selection: SidebarDestination?
    let onOpenSettings: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarDestination.all(for: sources)) { destination in
                row(destination).tag(destination)
            }

            // Settings sits below the destinations and outside the selection, because it
            // is a sheet the reader comes back from rather than a column they stay in. A
            // row that kept its highlight after the sheet closed would be claiming the
            // library was somewhere else.
            Section {
                Button(action: onOpenSettings) {
                    Label {
                        Text("library.settings", bundle: .module)
                            .foregroundStyle(theme.palette.textPrimary)
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text(verbatim: "StoryArc"))
    }

    @ViewBuilder
    private func row(_ destination: SidebarDestination) -> some View {
        switch destination {
        case .library:
            Label {
                Text("library.title", bundle: .module)
            } icon: {
                Image(systemName: "books.vertical")
            }
        case let .source(id):
            // The registry is what the list was built from, so this lookup cannot miss —
            // and if a source is removed between the two, the row is simply not drawn
            // rather than crashing on an index.
            if let source = sources.first(where: { $0.id == id }) {
                Label {
                    Text(source.displayName).lineLimit(1)
                } icon: {
                    Image(systemName: source.kind.symbolName)
                }
            }
        case .shelves:
            Label {
                Text("shelves.title", bundle: .module)
            } icon: {
                Image(systemName: "square.stack")
            }
        }
    }
}
