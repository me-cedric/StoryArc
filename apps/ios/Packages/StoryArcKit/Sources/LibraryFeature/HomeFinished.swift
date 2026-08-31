internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What the reader has finished, dated.
///
/// Last on the surface, and `home-screen` is explicit that it is absent when nothing has
/// been finished rather than shown as an empty heading. Apple Books' idea, and it costs
/// nothing here: `reading-progress` already stamps a completion date, so the only thing
/// missing was somewhere to show it — which turns the one dead state in a reading app into
/// something worth scrolling to.
///
/// Grouped by month rather than by day. A timeline with a heading over every single row is
/// a list wearing a timeline's clothes.
struct HomeFinished: View {
    @Environment(\.theme) private var theme

    let groups: [HomeShelves.FinishedGroup]
    let model: LibraryModel

    private var everything: [Publication] { groups.flatMap(\.publications) }

    var body: some View {
        HomeSection(title: Text("library.readState.finished", bundle: .module)) {
            HomeMore(
                title: Text("library.readState.finished", bundle: .module),
                publications: everything,
                model: model
            )
        } content: {
            VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                        Text(month(group.id))
                            .textRole(.subheadline)
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, StoryArcSpace.gutter)

                        HomeShelfRow(publications: group.publications, model: model)
                    }
                }
            }
        }
    }

    /// The month, written the way the reader's own language writes it.
    ///
    /// Formatted rather than translated: a month name is one of the things the system
    /// already knows in every language the app ships in, and a string table holding twelve
    /// of them per language would be four tables that can go out of step with the calendar.
    private func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(.storyArc))
    }
}
