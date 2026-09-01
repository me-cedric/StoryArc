public import Foundation

internal import UIKit

internal import ReadiumNavigator
internal import ReadiumShared
internal import ReadiumStreamer

public import Persistence
internal import Playback
public import StoryArcCore

/// One EPUB, open for reading.
///
/// `ebook-reader` requires reflowable EPUB 2 and 3 to render with real
/// typography, and ADR-0005 puts Readium behind that: laying out XHTML with
/// pagination, hyphenation and a stable position across a type-size change is a
/// rendering engine's job, not a weekend's work.
///
/// What is *not* Readium's job here is the library. `EpubReader` in `Formats`
/// still indexes the book — title, author, reading order, cover — with no
/// dependency and on the host, because that is all the shelf needs. This type
/// exists only from the moment someone opens one.
///
/// `@MainActor` because it is view state, and because the navigator is a
/// `UIViewController`.
@MainActor
@Observable
public final class EpubReaderModel {
    public let publication: StoryArcCore.Publication

    /// Set when the book could not be opened at all.
    public internal(set) var failure: String?

    /// How far through the whole publication, 0…1.
    ///
    /// `ebook-reader`: progress is a percentage, and "the app never presents a
    /// reflowable page number as a stable identity" — a reflowable page count
    /// depends on the type size, so there is no page number to present.
    public internal(set) var progression: Double = 0

    /// The chapter the reader is in, for the menu to name.
    public internal(set) var chapterTitle: String?

    /// How far through the current chapter, 0…1, or `nil` where Readium has not said.
    ///
    /// `ebook-reader` asks the progress line for "how much of the current chapter is left",
    /// and this is the only quantity a reflowable renderer can answer that with — it is
    /// within-*resource*, which is what a chapter is in an EPUB's reading order.
    /// ``ReadingPositionLine`` turns it into words.
    public internal(set) var withinChapter: Double?

    /// Which preset is on and which axes have been moved from it.
    public internal(set) var theme: ReadingTheme

    /// The typography in force: the preset's own values until an axis is moved.
    public internal(set) var values: ThemeValues

    /// Reader-local screen brightness, 0…1, or `nil` for the device's own.
    ///
    /// `reading-themes`: "reader-local screen brightness, independent of the system
    /// slider", and the system brightness "is not permanently modified". `nil` means
    /// the reader has not touched it, which is different from having set it to
    /// whatever the device happens to be at — the difference matters when the
    /// reader leaves and the original has to come back.
    public var brightness: Double?

    /// The navigator, once the book is open. `nil` while it is loading.
    internal(set) var navigator: EPUBNavigatorViewController?

    let url: URL
    let progress: ProgressStore?
    /// Where the reader's theme choices live between sessions. `nil` in a test.
    private let preferences: ReaderPreferences?
    /// The key this publication remembers its theme under.
    let shelf: String
    var locator: Locator?
    /// The reading order's hrefs, for the progress fallback below.
    var readingOrder: [String] = []

    /// Every mark in this publication, in book order.
    public internal(set) var annotations: [Annotation] = []

    /// Where the marks a reader makes live between sessions. Nil in a test.
    let annotationStore: AnnotationStore?

    /// What is selected, and where it is on screen, or nil when nothing is.
    ///
    /// `ebook-reader` wants a menu offering colours, a note, copy and search-in-publication.
    /// The system's own edit menu can hold none of that, so Readium is told not to show it
    /// and this is what the app's own menu is anchored to.
    var selection: Selection?

    /// A footnote the reader tapped, as text, or nil when none is open.
    ///
    /// `ebook-reader`: "a footnote opens in place as a popover". Readium fetches the note's
    /// markup and asks whether to navigate; answering no and showing this is what "in place"
    /// means — the reader keeps their page and their place in the sentence.
    public internal(set) var note: String?

    /// Where the book is asking to send the reader, or nil when it is not asking.
    ///
    /// A publication is untrusted input, and `ebook-reader` hands an external link to the
    /// system rather than opening it over the text. Handed straight over, that is the book
    /// choosing which installed app runs. So it becomes a question with the host in it, and
    /// nothing that is not a web address ever gets this far — see ``askToLeave(for:)``.
    public internal(set) var leaving: ExternalLink?

    /// Where the reader was before a jump, or nil when they have not jumped.
    ///
    /// `ebook-reader`: "a longer jump navigates with a control to return to where they
    /// were". One point rather than a stack: the control answers "take me back", and a
    /// reader who has followed four links in a row means the place they were reading, not
    /// the third link.
    public internal(set) var returnPoint: String?

    /// What the last search found, in the order the publication holds them.
    public internal(set) var matches: [SearchMatch] = []

    /// Whether a search is still running, so the list can say so rather than look empty.
    public internal(set) var isSearching = false

    /// Which search the results on screen belong to.
    ///
    /// A counter rather than a cancelled task: the walk is a sequence of `await`s inside one
    /// call, and the cheapest way to make an overtaken query stop publishing is to have it
    /// notice it has been overtaken.
    var searchGeneration = 0

    /// Every mark in this publication, in book order.
    public internal(set) var bookmarks: [Bookmark] = []

    /// Where the marks a reader makes live between sessions. Nil in a test.
    let bookmarkStore: BookmarkStore?

    /// The open publication, kept so a bookmark's excerpt can be read out of its resource.
    ///
    /// Held rather than reopened: opening parses the container, and this is wanted on a
    /// button press.
    ///
    /// `nonisolated(unsafe)` for the reason `SmbClient`'s client is: Readium's publication
    /// and the resources it hands out are plain classes from a library written before strict
    /// concurrency, and reading one is an `async` call that leaves this actor. Swift cannot
    /// see that only `excerpt(at:)` ever touches it, one call at a time, from a button a
    /// reader can only press once at a time.
    nonisolated(unsafe) var opened: ReadiumShared.Publication?

    /// Whether the voice is running, and what silenced it if it is not.
    ///
    /// Read from ``PlayerCentre`` rather than stored here, which is the whole of
    /// `ebook-reader`'s "the session SHALL outlive the screen it was started from": this
    /// screen observes the session, and does not own it. It is the *player's* session now —
    /// `audio-playback` allows one for everything that speaks — and ``ReadAloudCentre`` is
    /// asked which publication the voice is on, because a narrated audiobook drives the same
    /// centre and has no bar to offer inside a reader.
    ///
    /// Idle unless the book being spoken is *this* one. A reader looking at one book while
    /// another is being read aloud gets no transport in its chrome — the transport for the
    /// book being spoken is the one outside the reader, and a bar in here would offer to
    /// pause a book that is not on screen.
    var readAloud: PlaybackSession {
        ReadAloudCentre.shared.speaking == publication.id
            ? PlayerCentre.shared.session
            : PlaybackSession()
    }

    /// Whether this book can be spoken at all, and therefore whether the control appears.
    ///
    /// A stored, observed answer rather than `speech != nil`: the synthesizer is held
    /// outside observation — it is a reference to a Readium object, not view state — so a
    /// view asking it directly would never be told when it arrived, and the control would
    /// appear only when something else happened to redraw the chrome.
    public internal(set) var canReadAloud = false

    /// Readium's synthesizer, or `nil` when this publication has no content to speak.
    ///
    /// Built at open time rather than on the first press: the control has to know whether
    /// to appear at all before anyone touches it.
    ///
    /// Held only until a session starts. ``ReadAloudCentre`` takes a strong reference of its
    /// own when the session begins, which is what lets this screen — and this property —
    /// go while the voice carries on.
    @ObservationIgnored var speech: PublicationSpeechSynthesizer?

    /// The delegate that sets the speed of every utterance, built beside the synthesizer.
    ///
    /// Held here for the same reason ``speech`` is, and for one more: `AVTTSEngine` keeps its
    /// delegate **weakly**, so nothing but a strong reference outside the engine keeps it
    /// alive — and a deallocated one would leave every sentence after the first speaking at
    /// the platform default with nothing in a build to say so. ``ReadAloudCentre`` takes it
    /// over when a session begins, which is what lets this screen go.
    @ObservationIgnored var voice: SpokenVoice?

    /// The navigator's delegate, held separately.
    ///
    /// Readium's delegate protocols come from a module this package imports
    /// internally, so a `public` type cannot conform to one without re-exporting
    /// Readium to everything above. A small internal object conforms instead, and
    /// nothing outside learns which engine is rendering the page.
    @ObservationIgnored var observer: NavigatorObserver?

    /// - Parameter preferences: the store the theme is read from and written back
    ///   to. Passing `nil` gives a reader that forgets, which is what a test wants
    ///   and what the app had before themes persisted.
    public init(
        publication: StoryArcCore.Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        bookmarkStore: BookmarkStore? = nil,
        annotationStore: AnnotationStore? = nil,
        /// A preset the *app appearance* dictates, when the reader opted into that.
        ///
        /// `settings-and-about` keeps appearance and reading theme apart by default and
        /// allows "a single opt-in setting" that links them. When it is on, this is what
        /// the page is read with, and the shelf's own stored theme is *not* overwritten on
        /// open — so turning the setting off again brings it back.
        ///
        /// One edge, stated rather than glossed: adjusting a theme *while* linked does
        /// record it against the shelf, replacing what was there. That is the reader
        /// changing their mind on purpose, and a change that silently failed to stick
        /// would be the worse surprise.
        ///
        /// Passed in already resolved, because "System" is a question about the device.
        linkedPreset: ThemePreset? = nil
    ) {
        self.publication = publication
        self.url = url
        self.progress = progress
        self.preferences = preferences
        self.bookmarkStore = bookmarkStore
        self.annotationStore = annotationStore
        annotations = annotationStore?.annotations(for: publication.id) ?? []
        bookmarks = bookmarkStore?.bookmarks(for: publication.id) ?? []
        // Its series, or itself where it has none. `reading-themes` scopes a theme to
        // the series, and a standalone book is a series of one.
        self.shelf = ShelfMemory.shelf(series: publication.series, identity: publication.id)

        // The reflowable scope. A fixed-layout EPUB never reaches this reader —
        // `ebook-reader` sends it to the comic reader, which has pages.
        let stored = preferences?.themes().theme(for: Self.scope, shelf: shelf) ?? ShelfSettings()
        self.theme = linkedPreset.map { ReadingTheme(preset: $0) } ?? stored.theme
        self.values = linkedPreset?.values ?? stored.values
        self.transition = stored.transition
    }

    /// How a page becomes the next page. Paginated or scrolling, for an EPUB.
    public internal(set) var transition: PageTransition = .slide

    /// Whether StoryArc draws the turn rather than Readium.
    ///
    /// True only for the modes that need a picture of the page. Everything else stays with
    /// Readium's own paginated scroll, which is what Slide *is*.
    var ownsTheTurn: Bool { transition == .fastFade }

    /// Always reflowable. See the note in `init`.
    static let scope = ThemeScope.reflowable

    /// Adopts a preset, discarding any deviation from the last one.
    ///
    /// `reading-themes`: tapping a preset applies "every axis the preset defines at
    /// once and the change is visible immediately in the reader behind the sheet".
    public func adopt(_ preset: ThemePreset) {
        theme = theme.adopting(preset)
        values = preset.values
        applyTheme()
    }

    /// Sets one slider axis, in one call, so the sheet can drive nine of them.
    public func set(_ axis: ThemeAxis, to value: Double) {
        change(axis, to: values.setting(axis, to: value))
    }

    /// Moves one axis, which marks the preset modified without deselecting it.
    ///
    /// The axis is passed alongside the new values so the model records *which* axis
    /// moved — the sheet needs that to offer "restore this preset", and Readium
    /// cannot tell us.
    public func change(_ axis: ThemeAxis, to values: ThemeValues) {
        guard theme.isEffective(axis) else { return }
        self.values = values
        theme = theme.deviating(on: axis)
        applyTheme()
    }

    /// Puts every axis back to the preset's own values.
    public func restoreTheme() {
        theme = theme.restored()
        values = theme.preset.values
        applyTheme()
    }

    /// Which page-turn rows to offer, and which of them this content cannot run.
    ///
    /// - Parameter reduceMotion: read from the environment by the view, because that is
    ///   where a SwiftUI accessibility setting lives and where a change to it arrives.
    public func transitions(reduceMotion: Bool) -> TransitionChoices {
        TransitionChoices(
            chosen: transition,
            // Reflowing text scrolls the way it is read; the axis is not a choice here.
            axis: .vertical,
            reduceMotion: reduceMotion,
            // The curl over reflowable text needs the page rastered first, which is why
            // `isReflowable` refuses it below rather than this pretending it cannot curl
            // at all. The two reasons are different and the reader is told which.
            canCurl: true,
            // True, because this reader does take the turn over: see
            // `turnWithFade(forward:)`. A still of the outgoing page, then the navigator
            // moves with no animation of its own, then the still fades.
            canFade: true,
            isReflowable: true
        )
    }

    /// Chooses a page turn, for this shelf, from now on.
    public func choose(_ transition: PageTransition) {
        self.transition = transition
        remember()
        applyTheme()
    }

    /// Puts the reader's own colours in force, or refuses and says why.
    ///
    /// `reading-themes`: a pairing below 4.5:1 "is refused with the measured ratio
    /// stated". The refusal is returned rather than thrown or swallowed, because the
    /// sheet has to show the number — a refusal without one is just an obstacle.
    @discardableResult
    public func adoptColours(_ palette: ReaderPalette) -> Bool {
        guard palette.isReadable else { return false }
        theme = theme.adopting(palette)
        applyTheme()
        return true
    }

    /// Goes back to the preset's own colours, keeping its typography.
    public func discardCustomColours() {
        theme = theme.discardingCustomColours()
        applyTheme()
    }

    /// Turns publisher styles off by adopting a preset that overrides them.
    ///
    /// `reading-themes` requires an unavailable axis to offer "a single action that
    /// turns publisher styles off", and to preserve the reading position when it
    /// does. Readium re-lays out in place, so the position is kept by the navigator
    /// rather than by anything here.
    public func leavePublisherStyles() {
        guard theme.preset.keepsPublisherStyles else { return }
        adopt(.paper)
    }

    /// Writes the theme back, so the next book on this shelf opens the way this one
    /// was left.
    ///
    /// ponytail: reads and rewrites the whole blob per change. A drag now emits ten
    /// steps rather than one per frame, and the blob is a handful of small records,
    /// so this is cheaper than a debounce would be to get right. Debounce it if a
    /// reader with a thousand shelves ever notices.
    func remember() {
        guard let preferences else { return }
        let stored = ShelfSettings(theme: theme, values: values, transition: transition)
        preferences.save(
            preferences.themes().remembering(stored, for: Self.scope, shelf: shelf)
        )
    }

    func applyTheme() {
        remember()
        guard let navigator else { return }

        // Where the reader is, before the reflow moves it.
        //
        // `ebook-reader`: "the reading position is preserved to the paragraph, not
        // the page number". Submitting preferences re-paginates the resource, and
        // Readium lands on the *progression* rather than the paragraph — measured on
        // an emulator, a size change moved the reader fourteen paragraphs back
        // inside the same chapter. Going to the stored locator afterwards puts them
        // where the text was.
        let locator = navigator.currentLocation
        navigator.submitPreferences(theme.preferences(values: values, transition: transition))

        guard let locator else { return }
        // ponytail: after the reflow, not during it. `submitPreferences` has no
        // completion, so this waits a frame's worth rather than observing the
        // relayout. If Readium ever exposes a settled signal, wait on that instead.
        Task {
            try? await Task.sleep(for: .milliseconds(Self.reflowSettle))
            _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
        }
    }

    /// Long enough for Readium to re-paginate, short enough not to be seen.
    nonisolated private static let reflowSettle = 120
}
