internal import SwiftUI

internal import DesignSystem

/// Home when the reader owns nothing yet.
///
/// `home-screen`: with no publications at all "the home surface is itself the empty state —
/// one sentence, one action that opens a comic, one plain secondary that leads to connecting
/// a library", and the Library destination "is not offered as a wall of nothing".
///
/// So this is one sentence and two buttons, and pointedly not a menu of ways to connect
/// things. What it replaces on this surface is a taxonomy of four transports on a brand-new
/// reader's first screen, three of them unintelligible to the person reading them. Apple's
/// own onboarding guidance is essential information only, and not forcing setup before the
/// core function: opening a file is two taps to a readable page and configures nothing.
struct HomeEmpty: View {
    let onOpenFile: () -> Void
    let onAddFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("home.empty.title", bundle: .module)
            } icon: {
                Image(systemName: "book.closed")
            }
        } description: {
            Text("home.empty.body", bundle: .module)
        } actions: {
            // "Open a comic", not "Open a file". The design direction names the action in
            // the reader's terms, and the library's own empty state — the same situation on
            // the next destination along — now says exactly this. Two surfaces describing
            // one situation in two sets of words is how a four-language app drifts.
            Button(action: onOpenFile) {
                Text("library.openComic", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)

            // Plain, not a second prominent button: the reader who has just installed a
            // comic app wants to read a comic, and the shelf full of them can wait until
            // they know the app opens one.
            Button(action: onAddFolder) {
                Text("library.addFolder", bundle: .module)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: StoryArcSpace.huge * 8)
    }
}
