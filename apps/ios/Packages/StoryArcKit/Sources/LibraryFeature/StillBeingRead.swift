internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// How many sources have not put anything on the shelf yet.
///
/// **The silence this ends.** A reader adds a Kavita server, opens the library, and sees
/// the shelf they already had. Nothing says the server is still being read, and the client
/// waits twenty seconds before giving up — so for twenty seconds the app is
/// indistinguishable from one that ignored the source.
///
/// **Only a source that is still being asked.** A source that answered and holds nothing is
/// not waiting, and saying so for ever would be worse than saying nothing: the reader would
/// learn to ignore a line that is usually wrong. One that is unreachable is a different
/// sentence, which ``LibraryAway`` and the source's own screen already carry.
///
/// A local folder is never counted. Its publications arrive from a walk this app is
/// running, and the scan indicator already says so.
///
/// Pure, so the rule can be asserted without a shelf. ``StillBeingReadTests`` is that
/// assertion; Android's `sourcesStillBeingRead` is the twin.
func sourcesStillBeingRead(sources: [Source], publications: [Publication]) -> Int {
    let answered = Set(publications.compactMap(\.sourceID))
    return sources.count { source in
        source.kind != .localFolder && source.state == .connecting && !answered.contains(source.id)
    }
}

/// The line that says a source is still being read.
///
/// No source is named, for the reason a cover names none — the shelf does not say where a
/// publication came from, and a notice naming the one library still answering would put the
/// same fact back on the same screen.
struct StillBeingReadNotice: View {
    let waiting: Int

    var body: some View {
        Text("library.stillBeingRead \(waiting)", bundle: .module)
            .textRole(.footnote)
            .storyArcGlassText()
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .storyArcGlass()
            .accessibilityAddTraits(.isStaticText)
    }
}
