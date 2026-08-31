public import Foundation

#if os(iOS)
internal import MediaPlayer
#endif

/// What the lock screen says, and what its buttons reach.
///
/// **One of these, driven by ``PlayerCentre``, so both sources feed the same lock screen.**
/// `audio-playback` asks for the system's own controls to show "the cover, the publication,
/// the chapter, the elapsed and total time" and to "drive the same session, so using them
/// keeps the app's own surface in step" — and `ebook-reader` asks for exactly the same thing
/// for a synthesised voice. Two publishers would be two chances to disagree.
///
/// **The elapsed and total time are published only where they exist**, which is the same
/// rule the compact bar follows. A narrated file has a duration; a synthesised voice does
/// not, and `design.md` is explicit that a read-aloud session "shows position without a
/// total rather than inventing one". Publishing a zero duration is not neutral here: it
/// draws a scrubber pinned at the end of a bar that a listener can then drag.
///
/// The targets are added once for the life of the object rather than once per session —
/// `addTarget` appends, so wiring per play gave a listener who had started five books five
/// handlers on every button.
@MainActor
public final class NowPlaying {

    private weak var centre: PlayerCentre?
    private var isWired = false

    public init(publishing centre: PlayerCentre) {
        self.centre = centre
    }

    /// Puts what is playing on the lock screen and in Control Centre.
    public func publish() {
        #if os(iOS)
        guard let centre, let label = centre.book?.label else { return }
        wire()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: label.title,
            MPNowPlayingInfoPropertyPlaybackRate: centre.isPlaying ? centre.speed.rate : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: centre.time.elapsed,
        ]
        if let detail = label.detail { info[MPMediaItemPropertyArtist] = detail }
        // Only when it is known. See the type's note: a zero here is a scrubber, not a
        // blank.
        if let total = centre.time.total { info[MPMediaItemPropertyPlaybackDuration] = total }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = centre.isPlaying ? .playing : .paused
        #endif
    }

    /// Takes the book off the lock screen when the session ends.
    ///
    /// `audio-playback` requires the end of a book to withdraw the media controls "rather
    /// than offering to play a book that has run out of words".
    public func clear() {
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        let commands = MPRemoteCommandCenter.shared()
        for command in [
            commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
            commands.skipBackwardCommand, commands.skipForwardCommand,
            commands.nextTrackCommand, commands.previousTrackCommand,
            commands.changePlaybackPositionCommand,
        ] {
            command.isEnabled = false
        }
        #endif
    }

    #if os(iOS)
    /// Wires the buttons once, and enables the right ones for this session.
    ///
    /// **Which buttons depends on what the source can do, not on which source it is.** A
    /// narrated book gets skip-by-seconds and a scrubber; a synthesised voice gets
    /// sentence skip and no scrubber, because it has no seconds to scrub through. That is
    /// `audio-playback`'s "every control the player offers works, or is absent — none is
    /// present and refusing", applied to the lock screen.
    private func wire() {
        guard let centre else { return }
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true

        let byTime = centre.skipUnit == .time
        commands.skipBackwardCommand.isEnabled = byTime
        commands.skipForwardCommand.isEnabled = byTime
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: centre.skipIntervals.back)]
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: centre.skipIntervals.forward)]
        // Sentence skip, in the buttons the platform gives an audio app for it. A voice has
        // no tracks, so these are the only two controls a lock screen offers that mean
        // "move by one unit of the thing being played".
        commands.nextTrackCommand.isEnabled = !byTime
        commands.previousTrackCommand.isEnabled = !byTime
        commands.changePlaybackPositionCommand.isEnabled = centre.time.isScrubbable

        guard !isWired else { return }
        isWired = true

        commands.playCommand.addTarget { [weak self] _ in
            guard let centre = self?.centre, !centre.isPlaying else { return .commandFailed }
            centre.toggle()
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let centre = self?.centre, centre.isPlaying else { return .commandFailed }
            centre.toggle()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let centre = self?.centre else { return .commandFailed }
            centre.toggle()
            return .success
        }
        for (command, direction) in [
            (commands.skipBackwardCommand, SkipDirection.back),
            (commands.skipForwardCommand, SkipDirection.forward),
            (commands.previousTrackCommand, SkipDirection.back),
            (commands.nextTrackCommand, SkipDirection.forward),
        ] {
            command.addTarget { [weak self] _ in
                guard let centre = self?.centre else { return .commandFailed }
                centre.skip(direction)
                return .success
            }
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let centre = self?.centre,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            centre.scrub(to: event.positionTime)
            return .success
        }
    }
    #endif
}
