public import SwiftUI

internal import DesignSystem
public import Playback

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
    func playerSheet(isPresented: Binding<Bool>, centre: PlayerCentre) -> some View {
        modifier(PlayerSheetModifier(isPresented: isPresented, centre: centre))
    }
}

struct PlayerSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let centre: PlayerCentre

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                FullPlayerView(centre: centre)
                    .storyArcTheme()
            }
            // The player closes when the *session* ends, and on nothing else.
            //
            // A stable host does not tear itself down, which is the point — so the one case
            // that used to be handled by accident now has to be handled on purpose: a player
            // presented over a session that has finished is a dead player, with a scrubber for
            // audio that is gone.
            //
            // `isRunning` and not `isPlaying`: pausing is not ending, and this modifier
            // dismissing on a pause would be the original defect rebuilt by hand.
            // ``PlayerCentre/isRunning``'s own comment says why the shell reads that one.
            .onChange(of: centre.isRunning) { _, running in
                if !running { isPresented = false }
            }
    }
}
