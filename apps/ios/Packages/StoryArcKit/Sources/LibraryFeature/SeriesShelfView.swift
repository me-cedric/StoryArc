import DesignSystem
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
        seriesShelfMembers(named: name, in: model.publications)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                if !members.isEmpty {
                    ShelfOnDeviceLine(members, model: model)
                        .padding(.horizontal, StoryArcSpace.gutter)
                }
                CoverGrid(publications: members, model: model)
            }
        }
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // D36: "a status a source reports is not editable by the reader -- only a
            // series with no reported status takes one set by hand". The control is
            // withheld entirely for a reported series rather than shown disabled, the
            // same rule `design.md` gives every other control that would change nothing.
            if !model.seriesHasReportedStatus(name) {
                ToolbarItem {
                    SeriesStatusMenu(name: name, model: model)
                }
            }
        }
    }
}

/// The status a reader sets by hand, for a series with no reported one.
private struct SeriesStatusMenu: View {
    let name: String
    let model: LibraryModel

    private var current: PublicationStatus? { model.seriesStatuses[name] }

    var body: some View {
        Menu {
            ForEach(PublicationStatus.allCases, id: \.self) { status in
                Toggle(isOn: Binding(
                    get: { current == status },
                    set: { _ in model.setSeriesStatus(status, for: name) }
                )) {
                    Text(status.titleKey, bundle: .module)
                }
            }
            if current != nil {
                Divider()
                Button(role: .destructive) { model.clearSeriesStatus(name) } label: {
                    Text("library.series.status.clear", bundle: .module)
                }
            }
        } label: {
            Label {
                Text("library.series.status", bundle: .module)
            } icon: {
                Image(systemName: "tag")
            }
        }
    }
}

/// A series' own publications, in the library's `SERIES` order.
///
/// A free function beside the view rather than a method on it, so the ordering rule is
/// testable on its own: `library-browsing` says an opened series lists its issues "in their
/// own order", and that order is the library's `SERIES` comparison (number, then natural
/// filename), not adoption order. Android's `seriesShelfMembers` is its twin.
func seriesShelfMembers(named name: String, in publications: [Publication]) -> [Publication] {
    LibraryIndex.arrange(
        publications.filter { $0.series == name },
        query: LibraryQuery(sort: .series)
    )
}
