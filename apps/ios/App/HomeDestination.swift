import SwiftUI

import DesignSystem
import LibraryFeature
import StoryArcCore

/// Home: what the reader is in the middle of, and the way to everything else.
///
/// The first destination and where the app opens. There was no such screen before this
/// one — the closest thing was a *Continue reading* row inside the cover grid, hidden the
/// moment a search or a selection started, which took the app's one editorial moment away
/// exactly when a reader was looking hardest. It is assembled from the local reading
/// history alone and never waits on a server, which is the property `home-screen` names
/// and the one comparable apps get wrong.
///
/// It degrades by *absence*, not by emptiness: nothing in progress means no Keep reading
/// section rather than an empty one, and a library with nothing in it at all leaves one
/// line and the two ways out.
///
/// **This is a first pass, and says so.** The editorial Home the direction describes —
/// a paged carousel with cover-derived washes, *Up next* split from *Keep reading*, pinned
/// shelves, a finished timeline — is its own slice. What is here is the frame, real data
/// in it, and the two things that had nowhere else to go once the library's toolbar was
/// emptied: Settings and Shelves.
struct HomeDestination: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    let onOpen: (Publication, URL) -> Void
    let onOpenSettings: () -> Void

    /// The most recent arrivals, newest first.
    ///
    /// A projection over the library the app already holds, not a second query: `addedAt`
    /// is on the publication, and a shelf that had to ask a source for this would be a
    /// shelf that goes blank on a plane.
    private var recentlyAdded: [Publication] {
        model.publications
            .filter { $0.addedAt != nil }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(12)
            .map { $0 }
    }

    private var isBare: Bool { model.continueReading.isEmpty && recentlyAdded.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    if !model.continueReading.isEmpty {
                        HomeShelf(
                            title: Text("home.keepReading"),
                            publications: model.continueReading,
                            model: model,
                            onOpen: open
                        )
                    }
                    if !recentlyAdded.isEmpty {
                        HomeShelf(
                            title: Text("home.recentlyAdded"),
                            publications: recentlyAdded,
                            model: model,
                            onOpen: open
                        )
                    }
                    if isBare {
                        Text("home.nothingOpen")
                            .textRole(.callout)
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, StoryArcSpace.gutter)
                    }
                    shelvesLink
                }
                .padding(.vertical, StoryArcSpace.lg)
            }
            .frame(maxWidth: .infinity)
            .background(theme.palette.surfaceCanvas)
            // The same soft edge the shelf uses: what passes under this app's chrome is
            // artwork, and a hard cut across a cover looks like a rendering fault.
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle(Text("tab.home"))
            .toolbar {
                // The only trailing item, and the reason Settings could leave the
                // library's toolbar: it is not something done to the shelf.
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onOpenSettings) {
                        Label {
                            Text("home.settings")
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
    }

    /// Collections and reading lists, which the library's toolbar used to hold.
    ///
    /// A row on Home rather than a fourth destination: a shelf is something a reader made,
    /// so it belongs beside what they are reading, and `navigation-shell` is explicit that
    /// the destination set is three.
    private var shelvesLink: some View {
        NavigationLink {
            ShelvesView(model: model, onOpen: onOpen)
        } label: {
            HStack(spacing: StoryArcSpace.sm) {
                Image(systemName: "square.stack")
                Text("home.shelves")
                Spacer()
                Image(systemName: "chevron.right")
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
            }
            .foregroundStyle(theme.palette.textPrimary)
            .padding(.horizontal, StoryArcSpace.gutter)
            .frame(minHeight: StoryArcSpace.xxl)
        }
        .buttonStyle(.plain)
    }

    private func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }
}
