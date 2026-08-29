internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Every configured source, and what can be done to one.
///
/// `sources` requires the registry to be reachable, and until now it was not: the library's
/// own source list only appeared in a corner of its empty state, and this group said "not
/// built yet". The registry existed and nothing showed it.
///
/// Handed its data rather than owning it. A feature module never depends on another feature
/// module (docs/architecture), and the registry belongs to the library — so the app layer
/// passes it through and takes the removal back.
///
/// The icon and the state wording are mapped here rather than shared with the library's
/// `SourcePresentation`, for the reason that file gives: the domain enums live in core and
/// carry no resources, so each feature names them in its own catalogue.
struct SourcesSettings: View {
    @Environment(\.theme) private var theme

    let sources: [Source]
    /// How many publications each source holds, for the removal statement.
    let itemCount: (Source.ID) -> Int
    let onRemove: (Source) -> Void
    let onRename: (Source, String) -> Void

    /// Moves a source to the position a drag reports.
    ///
    /// `sources` describes reordering as a drag, and on this platform a drag is what a
    /// `List` already does — `onMove` also gives VoiceOver its own reorder actions, which a
    /// hand-rolled control would have to reimplement. Android has no equivalent and uses
    /// two buttons instead; `STATUS.md` records the difference.
    var onReorder: (Source.ID, Int) -> Void = { _, _ in }

    @State private var removing: Source?
    @State private var renaming: Source?
    @State private var draftName = ""

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    var body: some View {
        List {
            if sources.isEmpty {
                // A reader with no source is not looking at a broken screen. `sources`
                // wants the app usable "in under ten seconds", and the library's own empty
                // state is where a folder gets picked — so this points there rather than
                // duplicating the picker.
                Text("sources.none", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                ForEach(sources) { source in
                    row(source)
                }
                .onMove { indices, destination in
                    // One row moves at a time, because the list is not selectable.
                    guard let index = indices.first else { return }
                    onReorder(sources[index].id, destination)
                }
            }
        }
        // A drag needs edit mode, and edit mode needs a way in. Hidden below two sources,
        // because a list with one row has no order to change and a button that does
        // nothing is worse than no button.
        // `EditButton` is iOS-only, and this package also builds for macOS so the pure
        // targets can be tested on the host. The guard is the same one `ReaderFeature`
        // uses for its own iOS-only affordances.
        #if os(iOS)
        .toolbar {
            if sources.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        #endif
        // `sources` requires a rename to appear "everywhere the source is referenced",
        // which it does because the registry keeps the identifier and only the name moves.
        .alert(
            Text("sources.rename.title", bundle: .module),
            isPresented: isRenaming,
            presenting: renaming
        ) { source in
            TextField(
                String(localized: "sources.rename.field", bundle: .module, locale: .storyArc),
                text: $draftName
            )
            Button {
                onRename(source, draftName)
                renaming = nil
            } label: {
                Text("sources.rename.save", bundle: .module)
            }
            Button(role: .cancel) { renaming = nil } label: {
                Text("sources.rename.cancel", bundle: .module)
            }
        }
        .confirmationDialog(
            Text("sources.remove.title \(removing?.displayName ?? "")", bundle: .module),
            isPresented: Binding(
                get: { removing != nil },
                set: { if !$0 { removing = nil } }
            ),
            titleVisibility: .visible,
            presenting: removing
        ) { source in
            Button(role: .destructive) {
                onRemove(source)
                removing = nil
            } label: {
                Text("sources.remove", bundle: .module)
            }
        } message: { source in
            // `sources` asks the app to state what removal frees before asking. For a
            // folder that is nothing, and saying so is the point: a reader must not have to
            // guess whether this deletes their comics.
            Text("sources.remove.body \(itemCount(source.id))", bundle: .module)
        }
    }

    /// SF Symbols only, matching the library's own mapping. DESIGN.md §8.
    private static func symbol(for kind: SourceKind) -> String {
        switch kind {
        case .localFolder: "folder"
        case .networkShare: "externaldrive.connected.to.line.below"
        case .opdsCatalog: "dot.radiowaves.up.forward"
        case .kavitaServer: "server.rack"
        }
    }

    private static func status(of state: SourceConnectionState) -> LocalizedStringKey {
        switch state {
        case .connected: "sources.state.connected"
        case .connecting: "sources.state.connecting"
        case .unreachable: "sources.state.unreachable"
        case .unauthorized: "sources.state.unauthorized"
        }
    }

    @ViewBuilder
    private func row(_ source: Source) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            Image(systemName: Self.symbol(for: source.kind))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(source.displayName)
                    .foregroundStyle(theme.palette.textPrimary)
                // The state and the count, which is what `sources` asks a source's own
                // screen to show. Downloads are absent because nothing downloads yet, and
                // the count is what exists in their place.
                Text("sources.detail \(itemCount(source.id))", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }

            Spacer(minLength: 0)

            Text(Self.status(of: source.state), bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
        }
        // One control per row, announced once, and at least 44pt tall.
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { removing = source } label: {
                Text("sources.remove", bundle: .module)
            }
            Button {
                // Seeded with the current name rather than blank: a rename is usually a
                // correction, and retyping a folder's whole name to fix one letter is not.
                draftName = source.displayName
                renaming = source
            } label: {
                Text("sources.rename", bundle: .module)
            }
        }
    }
}
