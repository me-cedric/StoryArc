internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The whole of a Home shelf, when a reader asks a heading for the rest of it.
///
/// `home-screen` requires every shelf to lead "to the full list in the library, filtered to
/// match the shelf", and this is that list: the same grid, the same cells and the same way
/// in to a reader as the Library destination, over the shelf's own set. Reusing the grid is
/// the point rather than an economy — a *see all* that led to a second kind of shelf would
/// make the reader learn the same screen twice.
struct HomeMore: View {
    @Environment(\.theme) private var theme

    let title: Text
    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    var body: some View {
        CoverGrid(publications: publications, model: model, onOpen: onOpen)
            .background(theme.palette.surfaceCanvas)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle(title)
    }
}
