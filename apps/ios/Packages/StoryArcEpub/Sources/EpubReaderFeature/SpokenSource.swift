internal import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

internal import Playback
internal import StoryArcCore

/// The synthesised voice, as one of the player's two sources.
///
/// **This is what makes "both sources look the same" structural.** `audio-playback` requires
/// that "the surface, the controls and the lock-screen presentation are the same" whichever
/// produced the sound, and `design.md` answers that with one protocol and two
/// implementations rather than with a promise. `NarratedSource` is the other one. Neither
/// carries a `kind`, and no surface can ask which is speaking.
///
/// **It is deliberately thin.** Readium's `PublicationSpeechSynthesizer` still does the part
/// that is genuinely hard — walking the content across resource boundaries, splitting it
/// into sentences in the publication's own language, and handing back a `Locator` for each —
/// and ADR-0005 keeps that engine behind this package. What is here is the translation:
/// Readium's state into the player's ``PlaybackPlace``, and the player's transport into
/// Readium's.
///
/// **The two places the sources genuinely differ, and both are declared as data.** Its parts
/// carry no duration, because a voice does not know how long it will speak; and its
/// ``skipUnit`` is ``SkipUnit/sentence``, because a voice has no seconds to move by.
/// `PlayerCentre` reads both and draws accordingly — no scrub control, and skip labelled in
/// sentences — which is `audio-playback`'s "every control the player offers works, or is
/// absent — none is present and refusing", enforced without anything asking what is playing.
///
/// **Speed is the reason this could not be written before.** It is applied through
/// ``SpokenVoice``, the `AVTTSEngineDelegate` Readium points the caller at; see that type
/// for why the obvious property does not exist.
@MainActor
final class SpokenSource: PlaybackSource, PublicationSpeechSynthesizerDelegate {

    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?

    let parts: [PlaybackPart]
    private(set) var place: PlaybackPlace

    /// One sentence, which is all a synthesised voice can offer. See ``SkipUnit``.
    let skipUnit: SkipUnit = .sentence

    /// Nothing about a publication being read aloud can fail to decode: the book is open,
    /// and a resource the engine cannot speak ends the session rather than being counted.
    let unreadablePartCount = 0

    /// The sentence being spoken, whenever it changes.
    ///
    /// The reader draws it and the progress store records it, and neither is this type's
    /// business: a source produces sound, and a highlight belongs to a screen that may not
    /// exist. ``ReadAloudCentre`` is what wires the two.
    var onSentence: (@MainActor (Locator) -> Void)?

    /// The voice has gone quiet for good.
    ///
    /// Distinct from ``ended``, which tells the *player* the book ran out. This fires on
    /// every teardown, including the listener's own stop, and is what withdraws the
    /// highlight — `ebook-reader` requires the end to withdraw it "and the compact bar goes
    /// away with them".
    var onSilence: (@MainActor () -> Void)?

    private let speech: PublicationSpeechSynthesizer
    /// Held strongly for the life of the session: `AVTTSEngine` keeps its delegate weakly.
    private let voice: SpokenVoice
    /// The reading order: both the part list and where a row of the chapter list jumps to.
    private let links: [ReadiumShared.Link]
    /// The reading order's hrefs, which is what turns a locator into a part index.
    private let hrefs: [String]
    /// Where the reader was when they pressed play. `ebook-reader`: speech "begins at the
    /// current position", not at the top of the chapter.
    private let opening: Locator?
    private var hasStarted = false
    /// The sentence last reported, so a per-word state change is not a per-word redraw.
    private var spoken: Locator?

    init(
        speaking speech: PublicationSpeechSynthesizer,
        with voice: SpokenVoice,
        in publication: ReadiumShared.Publication,
        from locator: Locator?
    ) {
        self.speech = speech
        self.voice = voice
        links = publication.readingOrder
        opening = locator
        hrefs = publication.readingOrder.map(\.href)
        parts = SpokenParts.of(
            readingOrder: hrefs,
            titledBy: Self.navigation(of: publication)
        )
        place = PlaybackPlace(
            partIndex: Self.part(of: locator, in: hrefs),
            offset: 0
        )
        speech.delegate = self
    }

    // MARK: - The transport

    func play() {
        guard hasStarted else { return start(from: opening) }
        speech.resume()
    }

    func pause() { speech.pause() }

    func stop() {
        speech.delegate = nil
        speech.stop()
        onSilence?()
    }

    func setSpeed(_ speed: PlaybackSpeed) { voice.speak(at: speed) }

    /// Moves to a part, which for a publication read aloud is one resource of its reading
    /// order — the chapter list's own rows.
    ///
    /// The offset is ignored, and cannot be anything but zero: `PlayerCentre.scrub(to:)`
    /// refuses to reach a source whose part has no duration, so nothing can ask a voice to
    /// start ninety seconds into a chapter it has never measured.
    ///
    /// **The locator is built here rather than asked of `publication.locate(_:)`**, which is
    /// `async` and would mean sending a non-`Sendable` Readium publication into a task. It is
    /// the same locator: upstream's `locate(_:)` looks the href up in the manifest to find
    /// the resource link, and these *are* the resource links — they came out of the reading
    /// order, which is where it would have found them.
    func seek(toPart index: Int, offset: TimeInterval) {
        guard links.indices.contains(index), let mediaType = links[index].mediaType else { return }
        let link = links[index]
        start(
            from: Locator(
                href: link.url().removingFragment(),
                mediaType: mediaType,
                title: link.title,
                locations: Locator.Locations(progression: 0)
            )
        )
    }

    /// One sentence, in either direction.
    ///
    /// The interval is ignored — see ``skipUnit``. `audio-playback` requires a skip crossing
    /// a chapter boundary to continue "into the neighbouring one rather than stopping at the
    /// boundary", and Readium's own iterator does exactly that: it walks the publication's
    /// content, not one resource of it.
    func skip(_ direction: SkipDirection, by interval: TimeInterval) {
        guard hasStarted else { return start(from: opening) }
        switch direction {
        case .forward: speech.next()
        case .back: speech.previous()
        }
    }

    private func start(from locator: Locator?) {
        hasStarted = true
        speech.start(from: locator)
    }

    // MARK: - What Readium reports

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        switch state {
        case .stopped:
            // Readium stops itself at the end of the publication. `ebook-reader`: the voice
            // "stops, the highlight is withdrawn, and the media controls go away rather than
            // offering to play a book that has run out of words" — none of which this type
            // can do, so it says so and `PlayerCentre` does all three.
            ended?()
        case let .paused(utterance):
            reached(utterance.locator)
        case let .playing(utterance, range):
            // The range is the word being said inside the sentence. The sentence is what
            // gets drawn: a highlight that moved word by word over a paragraph is a karaoke
            // line, and this is a book.
            _ = range
            reached(utterance.locator)
        }
    }

    /// A sentence the engine could not say.
    ///
    /// Not a failure of the book: it is open and readable, and one unsupported language in
    /// one utterance is no reason to replace the page with an error. The session ends — with
    /// its position written, as every ending is — so the listener gets their play button back
    /// rather than a transport that does nothing.
    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        ended?()
    }

    /// Where the voice got to, in the two currencies that need it.
    ///
    /// **Two different rates, on purpose.** Readium republishes its state on every *word*,
    /// because that is how it reports the speaking range — so the sentence is deduplicated
    /// here, and the player is told only when the *part* changes. Without the first, the
    /// reader would redraw a decoration it had already drawn several times a second; without
    /// the second, the whole navigation would redraw with it, for a chapter name that had
    /// not changed.
    private func reached(_ locator: Locator) {
        guard locator != spoken else { return }
        spoken = locator
        onSentence?(locator)

        let next = PlaybackPlace(partIndex: Self.part(of: locator, in: hrefs), offset: 0)
        guard next != place else { return }
        place = next
        moved?()
    }

    // MARK: - Reading the publication

    /// Which resource of the reading order a locator is in.
    ///
    /// Zero when it is in none — a locator from a search or a link can be spelled a way the
    /// reading order is not, which `TotalProgression.index(of:in:)` already normalises. A
    /// part index has to be a real index: the chapter list is drawn from it.
    private static func part(of locator: Locator?, in hrefs: [String]) -> Int {
        guard let locator else { return 0 }
        return max(0, TotalProgression.index(of: locator.href.string, in: hrefs))
    }

    /// The publication's own navigation, flattened to href → title.
    ///
    /// Readium's, not ours. ADR-0005 leaves the EPUB's structure to the engine, and the
    /// `toc` collection is already parsed by the time the publication is open — so this
    /// reads it rather than opening the container a second time. What it means for a part is
    /// ``SpokenParts``'s decision, asserted on the host.
    private static func navigation(of publication: ReadiumShared.Publication) -> [String: String] {
        var titles: [String: String] = [:]
        func walk(_ links: [ReadiumShared.Link]) {
            for link in links {
                if let title = link.title, titles[link.href] == nil { titles[link.href] = title }
                walk(link.children)
            }
        }
        walk(publication.manifest.tableOfContents)
        return titles
    }
}
