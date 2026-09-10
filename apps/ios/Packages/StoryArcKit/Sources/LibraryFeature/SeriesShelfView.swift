import StoryArcCore
import SwiftUI

/// One series, and the publications inside it.
///
/// `library-browsing`: "when a reader opens a series, then its publications are listed in
/// their own order, each openable, each carrying the marks a cover carries in the grid",
/// and "one gesture returns to the library, at the place the reader left it" — which the
/// navigation stack's own back gesture is.
///
/// The same grid the library draws, given one series' members: a cell here and a cell there
/// must be the same thing, because a reader who has learned what a cover means in the
/// library has learned it here too. That is also why this screen has no sections, no sort
/// control and no filter — a series is already the answer to all three.
///
/// The members are read from the library rather than passed in, so a series opened before a
/// source finished answering fills in as the rest arrives. Android's `SeriesShelfScreen` is
/// its twin.
struct SeriesShelfView: View {
    let name: String
    let model: LibraryModel

    @Environment(\.theme) private var theme

    private var members: [Publication] {
        model.publications.filter { $0.series == name }
    }

    var body: some View {
        ScrollView {
            CoverGrid(publications: members, model: model)
        }
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
