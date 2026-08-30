public import Foundation

internal import AVFoundation
internal import MediaPlayer
internal import UIKit

internal import ReadiumNavigator
internal import ReadiumShared

internal import DesignSystem
public import StoryArcCore

// The book, read out loud.
//
// `ebook-reader`: speech "begins at the current position, the spoken sentence is
// highlighted, and the page follows", it keeps going when the app is backgrounded, and
// the platform's media controls carry the title and offer play, pause and sentence skip.
//
// Readium's `PublicationSpeechSynthesizer` does the part that is genuinely hard: walking
// the publication's content across resource boundaries, splitting it into sentences with
// the publication's own language, and handing back a `Locator` for each one. It also owns
// the `AVAudioSession`, which is why nothing here activates one. What is left is this
// app's: where to start, what to draw, where to move the page, what the lock screen says,
// and what an interruption does — the last of which lives in ``ReadAloudSession``.
//
// Android's `ReadAloudController` does the same job against the platform engine.

public extension EpubReaderModel {

    /// The group Readium draws the spoken sentence under.
    ///
    /// Its own group, beside `annotations`: the highlight follows the voice and is
    /// withdrawn when the voice stops, and neither of those should disturb a mark the
    /// reader made.
    private static var spokenGroup: String { "spoken" }

    /// Starts speaking from where the reader is.
    ///
    /// The current locator, not the top of the resource. A reader who presses play in the
    /// middle of a chapter means "from here", and starting at the chapter's first
    /// paragraph would make them listen back to what they have read.
    func startReadAloud() {
        guard let speech else { return }
        setUpRemoteCommands()
        readAloud = readAloud.started()
        speech.start(from: locator)
        publishNowPlaying()
    }

    /// Pause and play, from the reader's own control.
    func toggleReadAloud() {
        guard let speech else { return }
        if readAloud.isSpeaking {
            readAloud = readAloud.pausedByReader()
            speech.pause()
        } else {
            readAloud = readAloud.resumed()
            speech.resume()
        }
        publishNowPlaying()
    }

    /// Stops, clears the highlight, and hands the lock screen back.
    func stopReadAloud() {
        readAloud = readAloud.stopped()
        speech?.stop()
        spoken = nil
        clearSpokenHighlight()
        clearNowPlaying()
    }

    /// The next sentence, and the one before.
    ///
    /// Sentences rather than chapters: the spec calls it "sentence skip", and a reader
    /// reaching for skip during speech means the sentence they are on, not the chapter.
    func skipSentence(forward: Bool) {
        guard readAloud.isActive, let speech else { return }
        // Skipping while paused starts speaking again, which is what the gesture means:
        // nobody skips a sentence in order to keep hearing silence.
        readAloud = readAloud.started()
        if forward { speech.next() } else { speech.previous() }
        publishNowPlaying()
    }
}

extension EpubReaderModel {

    /// Builds the synthesizer once the publication is open.
    ///
    /// Called from ``EpubReaderModel/open()``'s tail rather than from `init`: there is no
    /// publication to speak before then, and `PublicationSpeechSynthesizer` refuses to be
    /// constructed for one it cannot extract content from — which is exactly the answer
    /// ``EpubReaderModel/canReadAloud`` needs.
    ///
    /// A fixed-layout EPUB never reaches this reader, and a reflowable one Readium can
    /// extract no content from is left with no control at all: `ebook-reader` says a
    /// control a platform cannot honour is absent rather than empty, and this app does
    /// not ship a play button that refuses.
    func prepareReadAloud(_ opened: ReadiumShared.Publication) {
        let listener = SpeechObserver(model: self)
        speechObserver = listener
        speech = PublicationSpeechSynthesizer(publication: opened, delegate: listener)
        canReadAloud = speech != nil
        guard canReadAloud else { return }
        observeInterruptions()
    }

    /// What the voice is on, so the transport can say it and the page can follow it.
    func speechAdvanced(to state: PublicationSpeechSynthesizer.State) async {
        switch state {
        case .stopped:
            // Readium stops itself at the end of the publication. Everything the reader's
            // own stop does has to happen here too, or the lock screen keeps offering to
            // play a book that has run out of words.
            guard readAloud.isActive else { return }
            stopReadAloud()

        case let .paused(utterance):
            spoken = utterance.locator
            await followSpokenSentence()

        case let .playing(utterance, range):
            // The range is the word being said inside the sentence. The sentence is what
            // gets drawn: a highlight that moved word by word over a paragraph is a
            // karaoke line, and this is a book.
            spoken = utterance.locator
            chapterTitle = utterance.locator.title ?? chapterTitle
            _ = range
            await followSpokenSentence()
        }
        publishNowPlaying()
    }

    /// Draws the sentence and brings the page to it.
    private func followSpokenSentence() async {
        guard let spoken, let navigator else { return }
        (navigator as (any DecorableNavigator)?)?.apply(
            decorations: [
                Decoration(
                    id: "spoken",
                    locator: spoken,
                    // The reader's own accent, at the weight a highlight uses. Underline
                    // rather than a block of colour would compete with the marks the
                    // reader made; a tint at the same weight reads as "this is where the
                    // voice is" without looking like something they can go back to.
                    style: .highlight(
                        tint: UIColor(
                            red: SpokenHighlight.red,
                            green: SpokenHighlight.green,
                            blue: SpokenHighlight.blue,
                            alpha: 1
                        ),
                        isActive: false
                    )
                ),
            ],
            in: Self.spokenGroup
        )
        // The page follows the voice, which is also what keeps the position record
        // honest: `reading-progress` writes on every navigator move, so a book listened
        // to for an hour resumes where the listening got to rather than where the reading
        // stopped.
        _ = await navigator.go(to: spoken, options: NavigatorGoOptions(animated: false))
    }

    private func clearSpokenHighlight() {
        (navigator as (any DecorableNavigator)?)?.apply(decorations: [], in: Self.spokenGroup)
    }
}

// MARK: - The lock screen

extension EpubReaderModel {

    /// What the publication is called while it is being spoken.
    var spokenLabel: SpokenLabel {
        SpokenLabel.of(
            title: publication.displayTitle,
            chapter: chapterTitle,
            author: publication.authors.first
        )
    }

    /// Puts the book on the lock screen and in Control Centre.
    ///
    /// No duration and no elapsed time: a book has no seconds, and a scrubber that
    /// pretended otherwise would be a control the reader could drag to a place this
    /// reader cannot honour. Progress goes in as the fraction it actually is.
    func publishNowPlaying() {
        let label = spokenLabel
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: label.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: readAloud.isSpeaking ? 1.0 : 0.0,
        ]
        if let detail = label.detail {
            info[MPMediaItemPropertyArtist] = detail
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = readAloud.isSpeaking ? .playing : .paused
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

    /// Wires the lock screen's buttons to this reader.
    ///
    /// Registered when speech starts rather than when the book opens: a reader who never
    /// presses play should not have their book appear in Control Centre.
    func setUpRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.togglePlayPauseCommand.isEnabled = true
        // Sentence skip, in the buttons the platform gives an audio app for it. A book
        // has no tracks, so these are the only two controls a lock screen offers that
        // mean "move by one unit of the thing being played".
        centre.nextTrackCommand.isEnabled = true
        centre.previousTrackCommand.isEnabled = true

        centre.playCommand.addTarget { [weak self] _ in
            guard let self, !readAloud.isSpeaking else { return .commandFailed }
            toggleReadAloud()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            guard let self, readAloud.isSpeaking else { return .commandFailed }
            toggleReadAloud()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            toggleReadAloud()
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            skipSentence(forward: true)
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            skipSentence(forward: false)
            return .success
        }
    }
}

// MARK: - Interruptions

extension EpubReaderModel {

    /// Listens for the audio being taken away and given back.
    ///
    /// `AVAudioSession.interruptionNotification` is the whole contract on iOS: a call, a
    /// timer, Siri, another app. The session itself is Readium's — it activates and
    /// deactivates one around each utterance — so this observes rather than manages.
    ///
    /// What happens next is ``ReadAloudSession``'s decision, not this method's.
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

    private func handleInterruption(
        _ type: AVAudioSession.InterruptionType,
        mayResume: Bool
    ) {
        switch type {
        case .began:
            guard readAloud.isSpeaking else { return }
            readAloud = readAloud.interrupted()
            speech?.pause()
            publishNowPlaying()

        case .ended:
            let next = readAloud.interruptionEnded(mayResume: mayResume)
            guard next != readAloud else { return }
            readAloud = next
            speech?.resume()
            publishNowPlaying()

        @unknown default:
            return
        }
    }

    /// Called when the screen goes away, so nothing outlives the book it is reading.
    func endReadAloud() {
        if let interruptions {
            NotificationCenter.default.removeObserver(interruptions)
            self.interruptions = nil
        }
        guard readAloud.isActive else { return }
        stopReadAloud()
    }
}

/// Readium's speech delegate, held by the model.
///
/// A separate object for the reason `NavigatorObserver` is one: the protocol comes from a
/// module this package imports internally, and a `public` type cannot conform to it
/// without re-exporting Readium to everything above.
@MainActor
final class SpeechObserver: PublicationSpeechSynthesizerDelegate {
    private weak var model: EpubReaderModel?

    init(model: EpubReaderModel) {
        self.model = model
    }

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        Task { await model?.speechAdvanced(to: state) }
    }

    /// A sentence the engine could not say.
    ///
    /// Not turned into `failure`: the book is open and readable, and one unsupported
    /// language in one utterance is not a reason to replace the page with an error. The
    /// session is stopped instead, so the reader gets their play button back rather than
    /// a transport that does nothing.
    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        Task { @MainActor in model?.stopReadAloud() }
    }
}
