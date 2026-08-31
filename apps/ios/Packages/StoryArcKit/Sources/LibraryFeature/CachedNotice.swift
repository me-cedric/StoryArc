internal import SwiftUI

internal import DesignSystem

/// States that the shelf on screen is last session's, and when it was confirmed.
///
/// `sources` asks for "a single unobtrusive indicator" saying "that content is cached and
/// when it was last refreshed". One line, in the secondary text colour, that leaves as soon
/// as a walk finishes — at which point the shelf is not cached, it is current, and a notice
/// still claiming otherwise would be the indicator lying quietly in the corner.
///
/// Not an error and not a warning. Offline is a normal state; so is a library that has not
/// been rewalked yet.
///
/// Its own file because it was written, translated into four languages, and mounted by
/// nothing. ``LibraryView`` now carries it in the bar below the shelf, which is where the
/// other quiet statements about the library already live, and it is the lowest-priority
/// branch there: a running selection or a folder that has gone missing is the more urgent
/// thing to say in the same strip.
struct CachedNotice: View {
    let refreshedAt: Date

    var body: some View {
        Text(
            "library.cached \(refreshedAt.formatted(.relative(presentation: .named)))",
            bundle: .module
        )
        .textRole(.footnote)
        // On glass, so the material decides rather than a fixed palette colour — see
        // ``ScanSummary`` for what a constant costs over a wall of moving cover art.
        .storyArcGlassText()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.xs)
        .storyArcGlass(in: Rectangle())
        .accessibilityAddTraits(.isStaticText)
    }
}
