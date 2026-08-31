internal import Foundation

internal import AVFoundation
internal import MediaPlayer

internal import ReadiumNavigator

internal import Playback

// The platform seam of a read-aloud session: what the lock screen says, what its buttons
// reach, and what happens when something else takes the audio.
//
// Split out of `ReadAloudCentre` so that file stays the *ownership* — who holds the
// session, who draws its sentence, where its position goes — and this one stays the two
// system centres and one notification the platform gives an audio app. They change for
// different reasons, which is the only reason worth splitting on.
//
// Android's half of the same seam is `ReadAloudService`, which is a foreground service
// because that is what Android gives an audio app instead.

extension ReadAloudCentre {

    // MARK: - The lock screen

    /// Puts the book on the lock screen and in Control Centre.
    ///
    /// No duration and no elapsed time: a book has no seconds, and a scrubber that
    /// pretended otherwise would be a control the listener could drag to a place this
    /// reader cannot honour.
    ///
    /// Deliberately **not** `MPNowPlayingInfoPropertyIsLiveStream`. It is the obvious flag
    /// for something with no duration, and on a locked simulator it drew the title and the
    /// chapter over a "LIVE" bar with no transport at all — iOS reads a live stream as
    /// something with no next and no previous, which is exactly the sentence skip
    /// `ebook-reader` asks the lock screen for.
    func publishNowPlaying() {
        guard let label = book?.label else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: label.title,
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? 1.0 : 0.0,
        ]
        if let detail = label.detail {
            info[MPMediaItemPropertyArtist] = detail
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isSpeaking ? .playing : .paused
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        let centre = MPRemoteCommandCenter.shared()
        for command in [
            centre.playCommand, centre.pauseCommand, centre.togglePlayPauseCommand,
            centre.nextTrackCommand, centre.previousTrackCommand,
        ] {
            command.isEnabled = false
        }
    }

    /// Wires the lock screen's buttons to whatever is speaking.
    ///
    /// The targets are added once for the life of the process rather than once per session.
    /// `addTarget` appends, and the reader used to call this on every play, so a listener
    /// who started five books had five handlers on every button. One owner is what makes
    /// registering once possible.
    ///
    /// The buttons themselves are still enabled per session, so a listener who never
    /// presses play does not have their book appear in Control Centre.
    func wireRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.togglePlayPauseCommand.isEnabled = true
        // Sentence skip, in the buttons the platform gives an audio app for it. A book has
        // no tracks, so these are the only two controls a lock screen offers that mean
        // "move by one unit of the thing being played".
        centre.nextTrackCommand.isEnabled = true
        centre.previousTrackCommand.isEnabled = true

        guard !isWired else { return }
        isWired = true

        centre.playCommand.addTarget { [weak self] _ in
            guard let self, !isSpeaking else { return .commandFailed }
            toggle()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            guard let self, isSpeaking else { return .commandFailed }
            toggle()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            toggle()
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            skip(forward: true)
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            skip(forward: false)
            return .success
        }
    }

    // MARK: - Interruptions

    /// Listens for the audio being taken away and given back.
    ///
    /// `AVAudioSession.interruptionNotification` is the whole contract on iOS: a call, a
    /// timer, Siri, another app. The session itself is Readium's — it activates and
    /// deactivates one around each utterance — so this observes rather than manages.
    ///
    /// What happens next is ``PlaybackSession``'s decision, not this method's.
    func observeInterruptions() {
        guard interruptions == nil else { return }
        interruptions = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let mayResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                .contains(.shouldResume)
            MainActor.assumeIsolated {
                self?.handleInterruption(type, mayResume: mayResume)
            }
        }
    }

    /// Taken down with the session rather than with a screen, which is what it used to
    /// follow. Nothing observes an interruption when nothing can be interrupted.
    func stopObservingInterruptions() {
        guard let interruptions else { return }
        NotificationCenter.default.removeObserver(interruptions)
        self.interruptions = nil
    }

    private func handleInterruption(
        _ type: AVAudioSession.InterruptionType,
        mayResume: Bool
    ) {
        switch type {
        case .began:
            guard isSpeaking else { return }
            interrupt()

        case .ended:
            // The three answers are ``PlaybackSession/endingInterruption(mayResume:)``'s,
            // not this method's. Before it existed there were two branches here, and an
            // `.ended` without `.shouldResume` matched neither: the session sat paused with
            // nothing able to start it and no position written, and the only way out was to
            // force-quit the app. Android has always answered the same event, as
            // `AUDIOFOCUS_LOSS`.
            switch endingInterruption(mayResume: mayResume) {
            case .nothing: return
            case .resume: resumeAfterInterruption()
            case .lost: lostAudio()
            }

        @unknown default:
            return
        }
    }
}

/// Readium's speech delegate, held by the centre.
///
/// A separate object for the reason `NavigatorObserver` is one: the protocol comes from a
/// module this package imports internally, and a `public` type cannot conform to it without
/// re-exporting Readium to everything above.
@MainActor
final class SpeechObserver: PublicationSpeechSynthesizerDelegate {

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        Task { await ReadAloudCentre.shared.speechAdvanced(to: state) }
    }

    /// A sentence the engine could not say.
    ///
    /// Not turned into `failure`: the book is open and readable, and one unsupported
    /// language in one utterance is not a reason to replace the page with an error. The
    /// session is ended instead — with its position written, as every ending is — so the
    /// listener gets their play button back rather than a transport that does nothing.
    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        Task { @MainActor in ReadAloudCentre.shared.end() }
    }
}
