public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// What the library shows before it shows publications: a walk in progress, a summary of
// what it skipped, and the two empty states — nothing added, and something added that has
// nothing on it. Split out of `LibraryView` for the same reason as the controls.
//
// It used to end with a list of configured sources and their connection dots. That is
// configuration, and §6.2 of the design direction puts configuration in Settings and
// nowhere else on the browse path; Settings › Your libraries has held the same list, with
// the same removal confirmation, the whole time.

/// While a scan runs.
///
/// `local-library` requires progress reported as a count of items found, and
/// requires that browsing what is already found is not blocked — so this is only
/// ever seen before the first publication arrives.
struct ScanningView: View {
    @Environment(\.theme) private var theme

    let state: LibraryScanState

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            ProgressView()
            if case let .scanning(found) = state {
                Text("library.scanning \(found)", bundle: .module)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

/// The first thing a reader ever sees when they own nothing.
///
/// `sources`, the *Adding the first source* scenario, states the whole of it: "one sentence
/// in plain language, one primary action that opens a comic from the device with nothing to
/// configure first, and one plain secondary action that leads to connecting a library", and
/// "the four source types are named only after that secondary action is taken".
///
/// What stood here was the opposite of every clause of that: four rows, one per transport,
/// three of them meaningless to the person reading them, two of them inert because the
/// feature behind them was not built — a taxonomy of protocols on a brand-new reader's very
/// first screen. Apple's onboarding guidance is essential information only, and not forcing
/// setup before the core function; opening a comic is two taps to a readable page and
/// configures nothing.
///
/// The four kinds live one level down, in ``AddSourceMenu``, where choosing between them is
/// the question actually being asked. That menu was written and translated and had no
/// caller anywhere in the app — the audit counted its strings among the nine that shipped
/// unreachable. This is its caller.
///
/// The sentence is `library.empty.*` and Home's is the same one, because Home *is* this
/// state when the library is empty (`home-screen`). It arrived as two near-identical pairs
/// — `home.empty.*` and `library.empty.*`, differing by a word in French and by a clause in
/// English — which is how one situation described twice in a four-language app drifts. One
/// pair now, on both destinations and both platforms.
struct EmptyLibraryView: View {
    /// The primary, and deliberately not a source: a file picker configures nothing and
    /// remembers nothing beyond the copy the app keeps.
    var openComic: () -> Void = {}

    var addFolder: () -> Void = {}
    var addCatalogue: () -> Void = {}
    var addKavita: () -> Void = {}
    var addShare: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("library.empty.title", bundle: .module)
            } icon: {
                Image(systemName: "book.closed")
            }
        } description: {
            Text("library.empty.subtitle", bundle: .module)
        } actions: {
            Button(action: openComic) {
                Text("library.openComic", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)

            // Plain, and second: a reader who has just installed a comic app wants to read
            // a comic, and the shelf full of them can wait until they know the app opens
            // one. `sources` calls this "one plain secondary action".
            AddSourceMenu(
                addFolder: addFolder,
                importFile: openComic,
                addCatalogue: addCatalogue,
                addKavita: addKavita,
                addShare: addShare
            )
        }
        .frame(maxWidth: StoryArcSpace.huge * 8)
        .reachableAtEveryTextSize()
    }
}

extension View {
    /// Lets an empty state scroll once the reader's text size makes it taller than the screen.
    ///
    /// `ContentUnavailableView` centres its contents and does not scroll them. At the largest
    /// Dynamic Type size that put the secondary action *behind the tab bar* — reachable by
    /// nobody, on the one screen whose whole job is to be reachable. Caught on a booted
    /// simulator at `accessibility-extra-extra-extra-large`, which is why AGENTS.md §6 asks
    /// for that size by name and why a `#Preview` would not have found it.
    ///
    /// A minimum height rather than a fixed one: at every ordinary size the view still fills
    /// the screen and stays centred, and the scroll view only has somewhere to go when the
    /// content genuinely outgrows it.
    func reachableAtEveryTextSize() -> some View {
        GeometryReader { proxy in
            ScrollView {
                frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sources are configured, and the shelf still has nothing on it.
///
/// Two ways to arrive, and they are not the same fact, so they do not get the same
/// sentence: either nothing the reader added can be reached, or the places are answering
/// and have sent nothing to this device yet. Telling a reader on a train that their library
/// is empty would be a lie about their books; telling a reader with a fresh, reachable
/// server that nothing can be reached would be a lie about their network.
///
/// What stood here was ``SourceList`` — the configured sources, their connection states and
/// a coloured dot each. That is the plumbing wearing the shelf's clothes, and §6.2 of the
/// design direction puts connections in Settings and nowhere else on the browse path. They
/// are still there, under Settings › Your libraries, with the same removal flow.
///
/// Never a dead end: one action asks every source again, one opens a comic that needs no
/// source at all. Offline is a normal state, so neither sentence is an error and neither is
/// red — see AGENTS.md §2.
struct LibraryAway: View {
    /// Whether nothing the reader added can be reached.
    ///
    /// Static and pure so the branch can be asserted without a window: which of the two
    /// sentences a reader is shown is the whole substance of this view, and a view is where
    /// a test cannot reach it. A local folder is marked `connected` the moment it is added,
    /// so a configured folder makes this false — which is right, because a folder with
    /// nothing in it has not gone away, it is empty, and those are two different sentences.
    nonisolated static func everythingAway(in registry: SourceRegistry) -> Bool {
        !registry.sources.isEmpty && registry.sources.allSatisfy { !$0.state.canFetch }
    }

    /// Whether *nothing* the reader added can be reached, as opposed to nothing having
    /// arrived yet from what can be.
    let isEverythingAway: Bool

    let retry: () -> Void
    let openComic: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("library.empty.title", bundle: .module)
            } icon: {
                Image(systemName: isEverythingAway ? "wifi.slash" : "books.vertical")
            }
        } description: {
            if isEverythingAway {
                Text("library.away.body", bundle: .module)
            } else {
                Text("library.pending.body", bundle: .module)
            }
        } actions: {
            Button(action: retry) {
                Text("source.offline.retry", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)

            Button(action: openComic) {
                Text("library.openComic", bundle: .module)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: StoryArcSpace.huge * 8)
        .reachableAtEveryTextSize()
    }
}

/// A folder that was remembered and can no longer be read.
///
/// `local-library`: "the source is marked `unauthorized` with a plain-language
/// explanation naming the folder", and "a single action re-picks the folder,
/// preserving reading progress for everything inside it". Progress survives
/// because ADR-0006 keys it on the publication, not on the folder.
struct UnavailableFolderNotice: View {
    let name: String
    let repick: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.sm) {
            Text("library.folderUnavailable \(name)", bundle: .module)
                .textRole(.footnote)
                // On glass, so the material decides rather than a fixed palette
                // colour — ``View/storyArcGlassText(_:)`` carries the argument.
                .storyArcGlassText()

            Spacer(minLength: 0)

            Button(action: repick) {
                Text("library.repick", bundle: .module)
                    .textRole(.footnote)
            }
        }
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.sm)
        // A capsule like the rest of this app's chrome. It keeps its width here, because a
        // sentence with an action beside it needs the room the sentence takes; what it
        // stops doing is running to both edges of the window.
        .storyArcGlass()
        .padding(.horizontal, StoryArcSpace.gutter)
    }
}
