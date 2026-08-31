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
/// simulator. Nothing here is asserted by a host test — an audio session cannot be
/// interrupted from one — and what *is* asserted is everything downstream of it, in
/// ``PlaybackSession`` and ``PlayerCentre``.
@MainActor
public final class PlaybackAudioSession {

    private weak var centre: PlayerCentre?
    private var interruptions: (any NSObjectProtocol)?
    private var routes: (any NSObjectProtocol)?

    public init(driving centre: PlayerCentre) {
        self.centre = centre
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
        #if os(iOS)
        guard interruptions == nil else { return }
        let session = AVAudioSession.sharedInstance()

        interruptions = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let mayResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                .contains(.shouldResume)
            MainActor.assumeIsolated { self?.interrupted(type, mayResume: mayResume) }
        }

        routes = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            MainActor.assumeIsolated { self?.routeChanged(reason) }
        }
        #endif
    }

    #if os(iOS)
    private func interrupted(_ type: AVAudioSession.InterruptionType, mayResume: Bool) {
        guard let centre else { return }
        switch type {
        case .began:
            centre.interrupt()

        case .ended:
            // The three answers are `PlaybackSession.endingInterruption(mayResume:)`'s, not
            // this method's. Two branches here is the shape that left a session paused for
            // ever with no position written, and the only way out was to force-quit.
            switch centre.endingInterruption(mayResume: mayResume) {
            case .nothing: return
            case .resume: centre.resumeAfterInterruption()
            case .lost: centre.lostAudio()
            }

        @unknown default:
            return
        }
    }

    /// `audio-playback`: headphones removed pauses, "because a book suddenly playing out
    /// loud is never what was intended", and "it does not resume by itself when they are
    /// reconnected".
    ///
    /// Only `.oldDeviceUnavailable`. The notification fires for every route change there
    /// is — a new device arriving, a category change, the app waking — and pausing on all of
    /// them would stop the book when the listener *plugged headphones in*, which is the
    /// opposite of what this exists for.
    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason) {
        guard reason == .oldDeviceUnavailable else { return }
        centre?.routeLost()
    }
    #endif
}
