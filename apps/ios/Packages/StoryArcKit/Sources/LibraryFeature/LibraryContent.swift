internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// What the library draws once there is something to draw: the grid, its empty
/// states, and the offer to put the same query to a server.
///
/// Split from `LibraryView.swift` when that file passed the length the linter allows.
/// The scene, its state, the split layout and the toolbar stayed there.
extension LibraryView {

    var content: some View {
        Group {
            KavitaServerSearchOffer(registry: model.registry, query: model.query) { source in
                serverSearch = model.query.search
                browsing = source.id
            }
            if !model.visible.isEmpty {
                if model.layout == .grid {
                    CoverGrid(
                        publications: model.visible,
                        // Hidden while a search or filter is running: the row is a shortcut
                        // to what you were reading, and showing publications the query
                        // excluded reads as a bug. Hidden while picking as well: a cover
                        // that opened the reader mid-selection would throw away everything
                        // the reader had chosen.
                        continueReading: model.query.isNarrowed || selection.isActive
                            ? []
                            : model.continueReading,
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
                        publications: model.visible,
                        groups: model.matchGroups,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) }
                    )
                }
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
                    // Offered only when there is somewhere wider to go. Written here from
                    // the start and never passed, so the button never drew.
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
