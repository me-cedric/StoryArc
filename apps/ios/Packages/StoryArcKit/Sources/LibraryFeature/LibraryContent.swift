internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// What the library draws once there is something to draw: the grid, its empty
/// states, and the offer to put the same query to a server.
///
/// Split from `LibraryView.swift` when that file passed the length the linter allows.
/// The scene, its state and the toolbar stayed there.
extension LibraryView {

    /// The publications this surface is about.
    ///
    /// A projection over the one library rather than a second store: `library-browsing`'s
    /// availability axis is *can I read this with no network*, and the answer is already
    /// on the device in the form of where each publication's bytes are. Everything the app
    /// can open from a file URL qualifies — a folder the reader picked as much as a
    /// download the app fetched — because that is the promise the destination makes, and
    /// a reader on a plane does not care which of the two put the file there.
    var shown: [Publication] {
        switch surface {
        case .onDevice: model.visible.filter { model.location(of: $0)?.isFileURL == true }
        case .shelf, .search: model.visible
        }
    }

    var content: some View {
        Group {
            KavitaServerSearchOffer(registry: model.registry, query: model.query) { source in
                serverSearch = model.query.search
                browsing = source.id
            }
            if !shown.isEmpty {
                if model.layout == .grid {
                    CoverGrid(
                        publications: shown,
                        // Empty, always. What the reader is in the middle of is the hero of
                        // the home destination now, and a second copy of it above the shelf
                        // was the app's only editorial moment being hidden the moment a
                        // search or a selection started — which is exactly when a reader is
                        // looking hardest.
                        continueReading: [],
                        // `library-browsing`: while a search is running, results are
                        // "grouped by match kind". Empty when nothing is typed, and then
                        // the shelf is one run of covers.
                        groups: model.matchGroups,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) }
                    )
                } else {
                    CoverList(
                        publications: shown,
                        groups: model.matchGroups,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) }
                    )
                }
            } else if surface == .onDevice {
                // Nothing to narrow and nothing to scan: this destination holds what the
                // device holds, so the only honest thing to say is that it holds nothing
                // yet. `navigation-shell` requires it to stay present and selectable
                // whatever the sources are doing, so there is no error branch here.
                OnDeviceEmpty()
            } else if !model.publications.isEmpty {
                // A library that is not empty but looks it. `library-browsing`
                // forbids showing that silently: say what is narrowing it and
                // offer one action to undo.
                NarrowedToNothing(
                    query: model.query,
                    clear: {
                        model.clearFilters()
                        model.query.search = ""
                    },
                    scopeName: model.registry.name(of: model.query.scope.sourceID),
                    // Offered only when there is somewhere wider to go.
                    widen: model.query.scope == .allSources
                        ? nil
                        : { model.widenToAllSources() }
                )
            } else if case .scanning = model.scanState {
                ScanningView(state: model.scanState)
            } else if model.registry.sources.isEmpty {
                EmptyLibraryView(
                    addFolder: { isPickingFolder = true },
                    addCatalogue: { isAddingCatalogue = true },
                    addKavita: { isAddingKavita = true }
                )
            } else {
                SourceList(
                    sources: model.registry.sources,
                    itemCount: { model.itemCount(of: $0) },
                    onRemove: { model.remove($0, credentials: credentials) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.surfaceCanvas)
        // `native-experience`: "floating chrome uses Liquid Glass, with scroll edge
        // effects at content boundaries". Soft rather than the default, because what
        // passes under this app's chrome is artwork — a hard cut across a cover looks
        // like a rendering fault, and a soft one reads as depth.
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

/// Nothing is on this device yet.
///
/// Its own small view rather than a bare `Text` so the destination has a centred, quiet
/// state at the weight the rest of the empty states use, and so the slice that turns this
/// destination into the full offline shelf has one place to grow it from.
struct OnDeviceEmpty: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("library.empty.title", bundle: .module)
            .textRole(.title3)
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
