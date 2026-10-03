public import SwiftUI

internal import DesignSystem
public import CoreGraphics
public import Playback
public import StoryArcCore

/// The full player's presentation, hosted by the shell rather than by the bar that opens it.
///
/// **This exists because of a defect, and the defect is worth keeping written down.** The
/// `.sheet` used to be attached inside ``PlayerDock``'s `dock(_:)` — which is reached through
/// `if let bar = centre.compact`. ``PlayerCentre/compact`` is *computed*: its value changes when
/// play/pause flips, and again every time the audio crosses a chapter. So the presentation's
/// host was destroyed by the very action taken inside the presentation. Pressing pause in the
/// full player put the listener back on the publication page with the bar still playing, and so
/// did tapping a chapter row. Reproduced on a device, and reproduced against the commit *before*
/// the Close pill was removed, so the pill was not the cause.
///
/// **Wrapping the dock's `if let` in a container would have fixed the teardown and broken
/// something else.** `PlaybackAccessory` in `AppShell` records that an empty accessory builder
/// still draws the glass capsule, and `audio-playback` requires the compact bar to be "absent
/// rather than present and empty" — so the dock's body must keep producing *nothing* when there
/// is nothing to draw. A host that is stable cannot also be a host that sometimes does not
/// exist. The two requirements are only compatible if the presentation moves out of the
/// accessory, which is what this does.
///
/// It is a modifier rather than a view so the app target does not have to import
/// `DesignSystem` to apply the theme, and so the rule below travels with the presentation
/// instead of being re-remembered at the call site.
public extension View {

    /// Presents the full player over this view.
    ///
    /// Attach it to something that outlives a session — the shell's own `TabView`. Attaching it
    /// to anything that reads ``PlayerCentre/compact`` reintroduces the defect above.
    ///
    /// - Parameters:
    ///   - next: what comes after the book that just finished, for the end-of-book offer.
    ///     `collections-and-reading-lists` task 7.2: the end of an audiobook offers what
    ///     comes next the way the paged reader's own end screen does. `nil` offers nothing.
    ///   - onOpenNext: what happens when the offer is taken.
    ///   - coverLookup: where the library's own cover for a publication comes from. Task
    ///     16.10. Defaulted to "no cover", which is what a caller with no library gets.
    ///   - onReturn: reopens a book being read aloud, after the sheet has gone. D17. `nil`
    ///     draws no way back in the player.
    func playerSheet(
        isPresented: Binding<Bool>,
        centre: PlayerCentre,
        next: Publication? = nil,
        onOpenNext: @escaping (Publication) -> Void = { _ in },
        coverLookup: @escaping (Publication, Int) async -> CGImage? = { _, _ in nil },
        onReturn: ((Publication, URL) -> Void)? = nil
    ) -> some View {
        modifier(
            PlayerSheetModifier(
                isPresented: isPresented,
                centre: centre,
                next: next,
                onOpenNext: onOpenNext,
                coverLookup: coverLookup,
                onReturn: onReturn
            )
        )
    }
}

struct PlayerSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let centre: PlayerCentre
    var next: Publication?
    var onOpenNext: (Publication) -> Void = { _ in }
    var coverLookup: (Publication, Int) async -> CGImage? = { _, _ in nil }
    var onReturn: ((Publication, URL) -> Void)?
    /// The book the player's way back chose. Opened in `onDismiss`, because a reader presented
    /// while this sheet is still up has nowhere to present from. D17.
    @State private var returning: SpokenBook?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: reopen) {
                FullPlayerView(
                    centre: centre,
                    next: next,
                    onOpenNext: onOpenNext,
                    coverLookup: coverLookup,
                    onReturn: onReturn == nil ? nil : { book in
                        returning = book
                        isPresented = false
                    }
                )
                .storyArcTheme()
            }
            // The player closes when the *session* ends for any reason but one.
            //
            // A stable host does not tear itself down, which is the point — so the one case
            // that used to be handled by accident now has to be handled on purpose: a player
            // presented over a session that has finished is a dead player, with a scrubber
            // for audio that is gone — *unless* the book ran out, in which case
            // ``FullPlayerView`` now draws the end-of-book offer instead of a dead scrubber,
            // and closing the sheet out from under it is the one case this exists to add.
            //
            // `isRunning` and not `isPlaying`: pausing is not ending, and this modifier
            // dismissing on a pause would be the original defect rebuilt by hand.
            // ``PlayerCentre/isRunning``'s own comment says why the shell reads that one.
            .onChange(of: centre.isRunning) { _, running in
                if !running, !centre.hasReachedTheEnd { isPresented = false }
            }
    }

    private func reopen() {
        guard let book = returning else { return }
        returning = nil
        onReturn?(book.publication, book.url)
    }
}
