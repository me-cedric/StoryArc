/// The platform's own half of a playback session.
///
/// Three moments, because there are three: the session started and the app should claim the
/// audio, something changed and the lock screen should say so, and the session ended and
/// both should be given back.
///
/// A protocol rather than a concrete type so ``PlayerCentre`` stays host-testable: there is
/// no `AVAudioSession` and no `MPNowPlayingInfoCenter` on the machine `pnpm test:ios` runs
/// on, and a centre that reached for either directly could be asserted nowhere.
@MainActor
public protocol PlaybackPlatform: AnyObject {
    /// Claim the audio and start listening for the platform taking it away.
    func sessionBegan()
    /// Something a listener could see has changed.
    func published()
    /// Give the audio back and take the book off the lock screen.
    func sessionEnded()
}

/// The audio session and the lock screen, as one thing to hand ``PlayerCentre``.
///
/// The two are separate types because they answer to different frameworks and change for
/// different reasons; they are wired together here because a session that claimed the audio
/// and never published, or published and never claimed, is broken in a way neither type can
/// see on its own.
@MainActor
public final class SystemPlaybackPlatform: PlaybackPlatform {
    private let audio: PlaybackAudioSession
    private let nowPlaying: NowPlaying

    public init(for centre: PlayerCentre) {
        audio = PlaybackAudioSession(driving: centre)
        nowPlaying = NowPlaying(publishing: centre)
    }

    public func sessionBegan() { audio.begin() }

    public func published() { nowPlaying.publish() }

    public func sessionEnded() {
        nowPlaying.clear()
        audio.end()
    }
}
