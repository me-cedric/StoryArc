public import Foundation

#if os(iOS)
internal import AVFoundation
#endif

/// The platform's audio session, and the two events it sends that a book has to answer.
///
/// **One of these for both sources, and that is the point.** The interruption rule and the
/// route rule were already implemented for read-aloud, in `ReadAloudControls.swift`, and
/// `design.md` is explicit that a narrated book must reuse them rather than grow a second
/// copy that can drift. Both now route into ``PlayerCentre``, whose ``PlaybackSession``
/// decides what a pause means — the decision this whole design keeps in one place.
///
/// `design.md`'s decisions, each at the line that implements it:
///
/// - Category **`.playback`**, so a book keeps playing when the screen locks.
/// - Mode **`.spokenAudio`**, which "exists for exactly this and gets the right ducking and
///   route behaviour" — a spoken-word app should duck under a navigation direction rather
///   than be stopped by it, and should not fight it for the route.
/// - Interruption via `AVAudioSession.interruptionNotification`, honouring `.shouldResume`.
/// - Route change via `AVAudioSession.routeChangeNotification` with `.oldDeviceUnavailable`
///   → pause.
///
/// It compiles on macOS with the audio-session calls absent: `AVAudioSession` is an iOS
/// type, and `StoryArcKit` builds for the host so its pure targets can be tested without a
/// simulator. The two notifications are read by ``AudioSessionEvent``, which has no
/// platform dependency, so a host test posts each one and asserts the session it reaches
/// (`AudioSessionEventTests`). Only the activation of the session itself is iOS-only.
@MainActor
public final class PlaybackAudioSession {

    private weak var centre: PlayerCentre?
    private var interruptions: (any NSObjectProtocol)?
    private var routes: (any NSObjectProtocol)?

    /// The sender the two notifications must name. The shared `AVAudioSession` on iOS; a host
    /// test passes its own object, so tests that run side by side do not hear each other.
    private let sender: AnyObject?

    public convenience init(driving centre: PlayerCentre) {
        #if os(iOS)
        self.init(driving: centre, postedBy: AVAudioSession.sharedInstance())
        #else
        self.init(driving: centre, postedBy: nil)
        #endif
    }

    init(driving centre: PlayerCentre, postedBy sender: AnyObject?) {
        self.centre = centre
        self.sender = sender
    }

    // No `deinit`, for the reason `NarratedSource` has none: Swift 6 forbids a nonisolated
    // one from reaching isolated state, and `end()` is called on every path that ends a
    // session — `PlayerCentre.finish` guarantees it through `sessionEnded()`.

    /// Claims the audio and starts listening. Called when a session begins.
    public func begin() {
        activate()
        observe()
    }

    /// Gives the audio back and stops listening. Called when a session ends.
    ///
    /// Nothing observes an interruption when nothing can be interrupted — the same rule the
    /// read-aloud session already followed, and the reason its observation was moved off the
    /// screen and onto the session in the first place.
    public func end() {
        if let interruptions { NotificationCenter.default.removeObserver(interruptions) }
        if let routes { NotificationCenter.default.removeObserver(routes) }
        interruptions = nil
        routes = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func activate() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        #endif
    }

    private func observe() {
        guard interruptions == nil else { return }

        interruptions = NotificationCenter.default.addObserver(
            forName: AudioSessionEvent.interruptionName,
            object: sender,
            queue: .main
        ) { [weak self] note in
            guard let event = AudioSessionEvent(interruption: note.userInfo) else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        }

        routes = NotificationCenter.default.addObserver(
            forName: AudioSessionEvent.routeChangeName,
            object: sender,
            queue: .main
        ) { [weak self] note in
            guard let event = AudioSessionEvent(routeChange: note.userInfo) else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    /// What each event means for the running session. The decisions are
    /// ``PlaybackSession``'s; this only routes them to ``PlayerCentre``.
    ///
    /// `audio-playback`: headphones removed pauses, "because a book suddenly playing out
    /// loud is never what was intended", and "it does not resume by itself when they are
    /// reconnected" — a pause recorded as the listener's.
    private func handle(_ event: AudioSessionEvent) {
        guard let centre else { return }
        switch event {
        case .interruptionBegan:
            centre.interrupt()

        case .interruptionEnded(let mayResume):
            // The three answers are `PlaybackSession.endingInterruption(mayResume:)`'s, not
            // this method's. Two branches here is the shape that left a session paused for
            // ever with no position written, and the only way out was to force-quit.
            switch centre.endingInterruption(mayResume: mayResume) {
            case .nothing: return
            case .resume: centre.resumeAfterInterruption()
            case .lost: centre.lostAudio()
            }

        case .routeLost:
            centre.routeLost()
        }
    }
}
