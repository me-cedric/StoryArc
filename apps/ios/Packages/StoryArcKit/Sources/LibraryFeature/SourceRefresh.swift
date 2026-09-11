internal import SwiftUI

internal import DesignSystem

/// Who started the refresh that is running now.
///
/// `sources`' *Refresh visibility* states one refresh once: a surface whose own gesture
/// already draws an indicator does not draw a second one. A pull draws the platform's own
/// spinner, so the only refresh the shelf's notice strip has to speak for is the one nobody
/// pulled — the library appearing, a source being added, the retry schedule, connectivity
/// regained, and the app returning to the foreground.
///
/// Android's `SourceRefreshOrigin` is the twin, and Android needed it first: `ShelfRefresh`
/// records that its pull indicator follows the folder walk alone, so a pull on a shelf
/// narrowed to a server retracts as the finger lifts, and names the fix — *"a signal that
/// tells a pull from the backoff loop"*. This is that signal.
enum SourceRefreshOrigin: Equatable {
    /// The reader pulled. The platform's spinner is this refresh's indicator.
    case pulled
    /// Nobody asked. The strip is this refresh's indicator.
    case automatic
}

/// What the shelf's notice strip says about its sources, and in what order.
///
/// Four things can be true at once and exactly one line is drawn, which makes this a
/// decision rather than a layout. Pure, and its own type, for the reason ``ShelfRefresh``
/// is: a decision written inside a view modifier is a decision nothing can assert.
/// Android's `LibraryNotice` holds the same five branches in the same order.
///
/// The bulk-selection bar and the missing-folder notice are not here. They outrank all of
/// these, they are not about sources, and they stay in the view that owns them.
enum LibraryNotice: Equatable {
    /// A source is still being read and has put nothing on the shelf yet.
    case stillBeingRead(Int)
    /// The shelf is last session's. That line already says "Checking for changes".
    case cached(Date)
    /// A refresh nobody asked for is running.
    case refreshing
    /// When the sources last answered.
    case checked(Date)
    /// Nothing worth saying.
    case none

    /// Which line the strip draws.
    ///
    /// The order is the ranking, and each step earns its place:
    ///
    /// 1. **A shelf that is incomplete** outranks everything. ``sourcesStillBeingRead``
    ///    counts a source that is `connecting` *and* has contributed nothing, which is the
    ///    silence after a server is added.
    /// 2. **A shelf that is last session's** comes next, and it is why there is no
    ///    double-statement here: `library.cached` already reads "Showing what was here …
    ///    Checking for changes", so a refreshing line above it would say the second half
    ///    twice.
    /// 3. **A refresh nobody pulled.** Not a pulled one — see ``SourceRefreshOrigin``.
    /// 4. **When the sources last answered.** The quietest thing the strip has to say, and
    ///    the one that answers "did it work" at any moment rather than for three seconds
    ///    after. `sources` asks the indicator to state "when it was last refreshed"; until
    ///    this line that was true only for a shelf that was offline.
    /// 5. **Nothing.** A library whose sources have never answered draws no indicator, per
    ///    *Nothing to say*.
    static func of(
        refreshing origin: SourceRefreshOrigin?,
        waiting: Int,
        cachedAt: Date?,
        checkedAt: Date?
    ) -> LibraryNotice {
        if waiting > 0 { return .stillBeingRead(waiting) }
        if let cachedAt { return .cached(cachedAt) }
        if origin == .automatic { return .refreshing }
        if let checkedAt { return .checked(checkedAt) }
        return .none
    }
}

/// The line that says a refresh nobody asked for is running.
///
/// Drawn like ``CachedNotice`` and ``StillBeingReadNotice``, because it takes their place in
/// the same strip and a reader should not be able to tell that three views are involved.
///
/// No source is named and no count is given. `sources`' non-goals say why the count is
/// absent: a server answers in one request and a folder walk answers in thousands, and those
/// are not the same unit.
struct RefreshingNotice: View {
    var body: some View {
        Text("library.refreshing", bundle: .module)
            .textRole(.footnote)
            .storyArcGlassText()
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .storyArcGlass()
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The line that says when the sources last answered.
///
/// Relative, and formatted at the moment it is drawn, so it is right whenever the strip is
/// laid out again. It does not tick on its own, and it does not need to: a line that is one
/// redraw behind still answers the question a line that vanished cannot answer at all.
struct CheckedNotice: View {
    let checkedAt: Date

    /// How recent counts as "just now".
    ///
    /// **Zero of a unit is never good copy, and this line met a reader at zero.**
    /// `.relative(presentation: .named)` says "now" for the first moments, which composes as
    /// "Libraries checked now." Android met the same fault with its own formatter and read
    /// "Libraries checked 0 minutes ago." on an emulator on 2026-09-11.
    ///
    /// Five seconds rather than one: the line is drawn when the shelf is laid out, not on a
    /// ticker, so a one-second window would be missed by the very redraw that follows a
    /// refresh. Android's `JUST_NOW_MILLIS` is the same number.
    private static let justNow: TimeInterval = 5

    /// The first seconds get a sentence of their own; everything after gets the platform's
    /// own phrasing, which `localization` requires rather than a duration this app assembles
    /// and then has to translate four times.
    private var sentence: LocalizedStringKey {
        guard Date.now.timeIntervalSince(checkedAt) >= Self.justNow else {
            return "library.checked.now"
        }
        return "library.checked \(checkedAt.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        Text(sentence, bundle: .module)
        .textRole(.footnote)
        .storyArcGlassText()
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.xs)
        .storyArcGlass()
        .accessibilityAddTraits(.isStaticText)
    }
}
