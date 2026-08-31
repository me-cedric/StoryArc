public import Foundation

internal import UIKit

internal import ReadiumNavigator
internal import ReadiumShared

internal import DesignSystem
internal import Playback
public import StoryArcCore

// The book, read out loud — as the reader screen sees it.
//
// `ebook-reader`: speech "begins at the current position, the spoken sentence is
// highlighted, and the page follows", it keeps going when the app is backgrounded, and the
// session "SHALL outlive the screen it was started from".
//
// That last clause is why almost nothing is left in this file. The session used to live on
// ``EpubReaderModel``, so dismissing the reader ended it; it now lives in
// ``ReadAloudCentre``, and what remains here is the half that genuinely needs a screen:
// starting from where the reader is, drawing the sentence, moving the page to it, and
// handing the session over rather than killing it on the way out.
//
// Readium's `PublicationSpeechSynthesizer` still does the part that is genuinely hard:
// walking the publication's content across resource boundaries, splitting it into sentences
// with the publication's own language, and handing back a `Locator` for each one. It also
// owns the `AVAudioSession`, which is why nothing here activates one.
//
// Android's `ReadAloudController` does the same job against the platform engine, and
// `ReadAloudHost` there holds it above the activity for the same reason this holds nothing.

public extension EpubReaderModel {

    /// The group Readium draws the spoken sentence under.
    ///
    /// Its own group, beside `annotations`: the highlight follows the voice and is withdrawn
    /// when the voice stops, and neither of those should disturb a mark the reader made.
    private static var spokenGroup: String { "spoken" }

    /// Starts speaking from where the reader is, and hands the session up.
    ///
    /// The current locator, not the top of the resource. A reader who presses play in the
    /// middle of a chapter means "from here", and starting at the chapter's first paragraph
    /// would make them listen back to what they have read.
    ///
    /// Everything the session will need once this screen is gone goes across in this one
    /// call — including where to write the position, because after it the reader is free to
    /// disappear and the voice is not.
    func startReadAloud() {
        guard let speech else { return }
        ReadAloudCentre.shared.begin(
            SpokenBook(publication: publication, url: url, chapter: chapterTitle),
            speaking: speech,
            recording: SpokenPosition(
                identity: publication.identity,
                readingOrder: readingOrder,
                store: progress
            ),
            drawnBy: self,
            from: locator
        )
    }

    /// Pause and play, from the reader's own control.
    func toggleReadAloud() { ReadAloudCentre.shared.toggle() }

    /// Stops, clears the highlight, and hands the lock screen back.
    func stopReadAloud() { ReadAloudCentre.shared.end() }

    /// The next sentence, and the one before.
    ///
    /// Sentences rather than chapters: the spec calls it "sentence skip", and a reader
    /// reaching for skip during speech means the sentence they are on, not the chapter.
    func skipSentence(forward: Bool) { ReadAloudCentre.shared.skip(forward: forward) }
}

extension EpubReaderModel {

    /// Builds the synthesizer once the publication is open, or picks up the one already
    /// speaking this book.
    ///
    /// Called from ``EpubReaderModel/open()``'s tail rather than from `init`: there is no
    /// publication to speak before then, and `PublicationSpeechSynthesizer` refuses to be
    /// constructed for one it cannot extract content from — which is exactly the answer
    /// ``EpubReaderModel/canReadAloud`` needs.
    ///
    /// A fixed-layout EPUB never reaches this reader, and a reflowable one Readium can
    /// extract no content from is left with no control at all: `ebook-reader` says a control
    /// a platform cannot honour is absent rather than empty, and this app does not ship a
    /// play button that refuses.
    func prepareReadAloud(_ opened: ReadiumShared.Publication) {
        let centre = ReadAloudCentre.shared
        let handover = SessionHandover.opening(publication.id, whilePlaying: centre.book?.id)

        // One book at a time. `ebook-reader`: opening a different publication "ends the
        // session at a sentence boundary and the position it reached is recorded before the
        // new publication opens" — and the sentence locator the voice is on *is* a sentence
        // boundary, which is what makes ending here honest rather than abrupt.
        if handover == .displace { centre.end() }

        // Built even when the session being adopted below is already speaking this book:
        // that session has a synthesizer of its own, but the moment a listener ends it this
        // screen is the one holding the play button, and a play button with no engine
        // behind it is the control `ebook-reader` refuses to ship.
        speech = PublicationSpeechSynthesizer(publication: opened, delegate: centre.speechDelegate)
        canReadAloud = speech != nil

        guard handover == .adopt else { return }
        // The book on screen is the book being spoken. No restart: the reader takes over
        // drawing the sentence the voice is already on, and the voice never notices.
        canReadAloud = true
        centre.adopt(self)
        Task { await centre.redrawSpokenSentence() }
    }

    /// Draws the sentence being spoken and brings the page to it.
    ///
    /// Called by ``ReadAloudCentre`` while this reader is the one on screen. When no reader
    /// is, nothing is drawn and nothing needs to be: the voice carries on, and the sentence
    /// is drawn again by whichever reader next adopts the session.
    func drawSpokenSentence(_ sentence: Locator) async {
        guard let navigator else { return }
        (navigator as (any DecorableNavigator)?)?.apply(
            decorations: [
                Decoration(
                    id: "spoken",
                    locator: sentence,
                    // The reader's own accent, at the weight a highlight uses. Underline
                    // rather than a block of colour would compete with the marks the reader
                    // made; a tint at the same weight reads as "this is where the voice is"
                    // without looking like something they can go back to.
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
        // The page follows the voice, which is also what keeps this screen's own position
        // record honest: `reading-progress` writes on every navigator move. The session
        // writes for itself as well, because a listener with no reader on screen has no
        // navigator to move — see ``SpokenPosition``.
        _ = await navigator.go(to: sentence, options: NavigatorGoOptions(animated: false))
    }

    /// Takes the spoken highlight off the page when the voice stops.
    func withdrawSpokenHighlight() {
        (navigator as (any DecorableNavigator)?)?.apply(decorations: [], in: Self.spokenGroup)
    }

    /// Called when the screen goes away.
    ///
    /// It lets go of the session; it does not end it. `ebook-reader`: closing the
    /// publication while the voice is speaking leaves speech running and returns the
    /// listener "to whatever they were doing in the app rather than being kept in the book".
    /// This method used to call `stopReadAloud`, and that one line was the whole defect —
    /// leaving the book was leaving the audio.
    ///
    /// A reader that never started a session, or whose session was displaced by another
    /// book, releases nothing: ``ReadAloudCentre/release(_:)`` only lets go of the screen it
    /// is actually being drawn by.
    func detachReadAloud() {
        ReadAloudCentre.shared.release(self)
        speech = nil
    }
}
