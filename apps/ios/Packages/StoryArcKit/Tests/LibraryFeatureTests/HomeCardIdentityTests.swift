import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The two lines a hero card sets around its title.
///
/// `home-screen`, *The card shows how far through, not only how much is left*: "the
/// publication's author is named where the card has room for it, because a title alone is
/// not enough to recognise a book by". The rule has one condition in it, and the condition
/// is the part worth pinning — a byline that repeated the kicker would be one fact set
/// twice on a card whose whole job is to be recognised at a glance.
@Suite("A hero card names the book and who wrote it")
struct HomeCardIdentityTests {

    private func publication(
        title: String,
        series: String? = nil,
        authors: [String] = [],
        publisher: String? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            series: series,
            authors: authors,
            publisher: publisher,
            origin: .inferred
        )
    }

    @Test("The author is named")
    func authorIsNamed() {
        let item = publication(title: "Ember Lines #2", series: "Ember Lines", authors: ["A. Vance"])

        #expect(HomeCardIdentity.byline(of: item) == "A. Vance")
    }

    @Test("A publication with no author gets no line rather than a blank one")
    func noAuthorIsNoLine() {
        // A row held open for the books that have no author is a gap a reader reads as a
        // bug, and a folder library is mostly books with no author.
        #expect(HomeCardIdentity.byline(of: publication(title: "Vol 3")) == nil)
        #expect(HomeCardIdentity.byline(of: publication(title: "Vol 3", authors: [""])) == nil)
    }

    @Test("The first author, as every other cell in this app shows")
    func theFirstAuthorOnly() {
        let item = publication(title: "Vol 3", authors: ["A. Vance", "M. Okonjo", "T. Reyes"])

        #expect(HomeCardIdentity.byline(of: item) == "A. Vance")
    }

    @Test("An author who is also the kicker is not set twice")
    func theKickerIsNotRepeated() {
        // A self-published author is their own publisher, and the publisher is what the
        // kicker falls back to. The card would then read the same name in small caps above
        // the title and again under it.
        let item = publication(title: "Vol 3", authors: ["A. Vance"], publisher: "a. vance")

        #expect(HomeCardIdentity.kicker(of: item) == "a. vance")
        #expect(HomeCardIdentity.byline(of: item) == nil)
    }

    @Test("A series kicker never suppresses the byline, because they are different facts")
    func seriesDoesNotSuppress() {
        let item = publication(title: "#2", series: "Ember Lines", authors: ["Ember Lines"])

        #expect(HomeCardIdentity.kicker(of: item) == "Ember Lines")
        #expect(HomeCardIdentity.byline(of: item) == nil)
    }

    @Test("A title that already carries the series takes the publisher as its kicker")
    func kickerFallsBackToPublisher() {
        // Most of a folder library: a title guessed from a filename is the series and the
        // issue joined back together, and setting the series over it is an echo.
        let item = publication(title: "Ember Lines #2", series: "Ember Lines", publisher: "Kite")

        #expect(HomeCardIdentity.kicker(of: item) == "Kite")
    }

    @Test("A publication with neither a series to add nor a publisher gets no kicker")
    func noKicker() {
        #expect(HomeCardIdentity.kicker(of: publication(title: "Vol 3")) == nil)
    }
}

/// That the hero draws the progress it is given.
///
/// `home-screen` asks for progress to be "visible as well as stated — a reader glancing at
/// the surface can see roughly where they are without reading the line". A bar is a drawn
/// thing and the proof of a drawn thing is a screenshot; this is the smaller guard that
/// catches the regression a screenshot would only catch if somebody took another one. It
/// asserts the wiring, not the pixels.
@Suite("The hero card is wired to the reading position")
struct HomeHeroProgressWiringTests {

    /// `#filePath` rather than a walk that climbs looking for a known folder: agents work
    /// in worktrees under `.claude/worktrees/`, and a climbing walk leaves the checkout
    /// under test and validates the parent repository's copy instead. `#filePath` is fixed
    /// at compile time to the source that was compiled, so it cannot leave its own tree.
    private func heroSource() throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/HomeHero.swift").path
        return try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            """
            \(path) could not be read — has HomeHero.swift moved? \
            A guard that cannot find what it guards passes for ever.
            """
        )
    }

    @Test("The card asks the model how far through the reader is, and draws it")
    func drawsAFractionItAsksFor() throws {
        let text = try heroSource()

        #expect(text.contains("model.readFraction(of: publication)"))
        #expect(text.contains("progressBar(fraction)"))
    }

    @Test("The bar is not announced, because the line beside it already says the same thing")
    func theBarIsNotSpokenTwice() throws {
        // A bar reporting "58 per cent" beside a line reading "42 pages left" is one fact
        // in two units, and `home-screen` names the percentage as the thing not to say.
        #expect(try heroSource().contains(".accessibilityHidden(true)"))
    }

    @Test("There is a named action, and it does what the tap does")
    func theButtonDoesWhatTheTapDoes() throws {
        // `home-screen`, *Resuming is an action, not only a target*: the card "carries a
        // named action that resumes, as well as being tappable itself", and "the two do the
        // same thing". Both paths call `onOpen(publication)` — not two routes to one book
        // that could one day disagree about which page it opens at.
        let text = try heroSource()

        #expect(text.contains("home.resume"))
        #expect(text.contains(".buttonStyle(.glassProminent)"))
        #expect(text.contains("onTapGesture { if isReadable { onOpen(publication) } }"))
        #expect(text.contains("onOpen(publication)"))
    }

    @Test("A book that cannot be opened is offered no action that would do nothing")
    func noActionWhereThereIsNoBook() throws {
        // The card stays on the shelf, dimmed — `home-screen` insists on that. What it must
        // not do is offer a button that fails, when the line above already says why.
        #expect(try heroSource().contains("if isReadable {\n                resumeButton"))
    }
}
