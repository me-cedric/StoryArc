internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The sources that were asked and have never answered, named in the order they were added.
///
/// `library-browsing`'s *A source that has never been reached*: the library says that source
/// has not been read yet, names it, and offers to try again. Until this function the shelf
/// said nothing at all for that source. ``LibraryNotice/of(refreshing:waiting:cachedAt:checkedAt:)``
/// returns `.none` when no source has ever answered, ``sourcesStillBeingRead(sources:publications:)``
/// returns a count and drops every name, and ``LibraryAway`` draws a sentence that names
/// nobody and is reached only when the shelf is empty.
///
/// **Three states are deliberately not this sentence.**
///
/// 1. `connecting` is ``sourcesStillBeingRead(sources:publications:)``'s. The source is being
///    asked now, so "has not been read yet" would race the answer. This also gives the retry
///    its feedback: a probe marks the source `connecting`, this list empties, and the
///    still-being-read line takes over until the probe lands.
/// 2. `unauthorized` needs a sign-in. `SourceConnectionState.needsUserAction` names that state
///    alone, and a *Try again* that cannot change the answer is a button that teaches a reader
///    to distrust buttons.
/// 3. A source that answered before is away, not unread. `SourceRegistry.marking(_:as:at:)`
///    stamps `lastSuccessfulSync` on every `connected` answer and keeps the stamp through a
///    later refusal, so a nil stamp is the record that nothing ever arrived.
///
/// A local folder is never named. It is marked connected the moment it is added, so it is
/// never a place that has failed to answer.
///
/// Pure, so the rule can be asserted without a window. ``NeverReachedTests`` is that
/// assertion; Android's `sourcesNeverReached` is the twin.
func sourcesNeverReached(in sources: [Source]) -> [String] {
    sources.filter { source in
        guard source.kind != .localFolder, source.lastSuccessfulSync == nil else { return false }
        if case .unreachable = source.state { return true }
        return false
    }
    .map(\.displayName)
}

/// The line that names a source the library has never read, and offers to ask it again.
///
/// Drawn like ``UnavailableFolderNotice``, because it is the same shape: a sentence naming a
/// place, with one action beside it. Offline is a normal state, so this is footnote text on
/// glass and not an error — see AGENTS.md §2.
///
/// One row for all of them rather than one row each. ``SearchResultsView`` records what the
/// other arrangement costs: three servers configured and none answering produced three
/// notices with three *Try again* buttons, and the notices outnumbered the answers. A
/// locale-aware list keeps one sentence and adds no string to translate.
///
/// Android's `NeverReachedNotice` is the twin. It joins the names with a comma, because
/// Compose reads its sentence out of `strings.xml` and has no list formatter in its way.
struct NeverReachedNotice: View {
    let names: [String]
    let retry: () -> Void

    /// The unread libraries as one phrase, in the reader's own language.
    ///
    /// `.storyArc` rather than the process locale, the way every other string in this module
    /// is resolved: the app's language is the reader's choice and not the device's.
    ///
    /// Static so the join can be asserted on the host — this is the part that decides whether
    /// one notice reads as a sentence or as a list of identifiers.
    static func named(_ names: [String]) -> String {
        names.formatted(.list(type: .and).locale(.storyArc))
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // **Stacked at the accessibility sizes, because the name is the whole sentence.**
        // Side by side at `AccessibilityXXXL` the sentence was cut to "Cellar Catalogue…" —
        // the name truncated and *hasn't been read yet* gone altogether, which leaves a
        // reader with a fragment and a button.
        //
        // `isAccessibilitySize` rather than `ViewThatFits`, for the reason ``SourceDetail``
        // gives about its own fields: the fallback is a different row rather than the same
        // row narrower.
        //
        // **The bottom bar's height is capped, and this is not fixed.** Photographed at
        // `AccessibilityXXXL` on 2026-09-12: the sentence now reads in full and *Try again*
        // is painted under the floating tab bar, because `safeAreaBar` gives this strip a
        // height the stacked layout exceeds. `ViewThatFits` and `fixedSize` were both tried
        // and neither moved it, so the cap is the bar's rather than this view's — and
        // ``UnavailableFolderNotice``, the same sentence-plus-action shape in the same bar,
        // has the same limit. The sentence is what wins the trade, because it is the only
        // place this source is named; the retry has two other routes, the pull on the shelf
        // and ``LibraryAway``'s own button.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    sentence
                    action
                }
            } else {
                HStack(spacing: StoryArcSpace.sm) {
                    sentence
                    Spacer(minLength: 0)
                    action
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.sm)
        .storyArcGlass()
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    private var sentence: some View {
        Text("library.neverReached \(Self.named(names))", bundle: .module)
            .textRole(.footnote)
            .storyArcGlassText()
            // Wrapped rather than shortened. A sentence this narrow has nothing to spare.
            .fixedSize(horizontal: false, vertical: true)
    }

    private var action: some View {
        Button(action: retry) {
            Text("source.offline.retry", bundle: .module)
                .textRole(.footnote)
        }
    }
}
