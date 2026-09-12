import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which sources the library says it has never read.
///
/// `library-browsing`'s *A source that has never been reached*: the library "says that source
/// has not been read yet, names it, and offers to try again". The name is the part nothing
/// carried before — ``sourcesStillBeingRead(sources:publications:)`` returns a count,
/// ``LibraryNotice`` returns `.none`, and ``LibraryAway`` draws a sentence that names nobody.
///
/// **The four cases that must not be named are the point of the test.** A source that
/// answered once is away rather than unread; a source still being asked is the
/// still-being-read sentence; a source that needs a sign-in needs an action *Try again*
/// cannot supply; and a local folder is connected the moment it is added.
///
/// Android's `NeverReachedTest` asserts the same six cases.
@Suite("What the library has never read")
struct NeverReachedTests {

    private func source(
        kind: SourceKind = .kavitaServer,
        state: SourceConnectionState = .unreachable(since: .distantPast),
        answeredAt: Date? = nil,
        name: String = "Attic NAS"
    ) -> Source {
        Source(
            displayName: name,
            kind: kind,
            state: state,
            lastSuccessfulSync: answeredAt,
            locator: "https://x.invalid"
        )
    }

    @Test("A server that was asked and never answered is named")
    func neverAnswered() {
        #expect(sourcesNeverReached(in: [source()]) == ["Attic NAS"])
    }

    @Test("A server that answered before is away rather than unread, so it is not named")
    func answeredOnce() {
        // The stamp is the record. `SourceRegistry.marking(_:as:at:)` writes it on every
        // connected answer and keeps it through a later refusal, so a source with a stamp has
        // been read once — telling that reader it "has not been read yet" would be false.
        #expect(sourcesNeverReached(in: [source(answeredAt: .distantPast)]).isEmpty)
    }

    @Test("A server still being asked is not named, because that is the other sentence")
    func stillBeingAsked() {
        // ``sourcesStillBeingRead(sources:publications:)`` carries this one. It also makes the
        // retry legible: a probe marks the source connecting, this list empties, and the
        // still-being-read line takes over until the probe lands.
        #expect(sourcesNeverReached(in: [source(state: .connecting)]).isEmpty)
    }

    @Test("A server that needs a sign-in is not named, because trying again cannot answer it")
    func unauthorized() {
        let refused = source(state: .unauthorized(reason: "Sign-in needed"))

        #expect(sourcesNeverReached(in: [refused]).isEmpty)
    }

    @Test("A local folder is never named, because it is connected the moment it is added")
    func aFolder() {
        #expect(sourcesNeverReached(in: [source(kind: .localFolder)]).isEmpty)
    }

    @Test("Two unread servers are both named, in the order they were added")
    func two() {
        let first = source(name: "Attic NAS")
        let second = source(name: "StoryArc Test Catalogue")

        #expect(sourcesNeverReached(in: [first, second]) == ["Attic NAS", "StoryArc Test Catalogue"])
    }

    @Test("Every unread library is named in one sentence")
    func joined() {
        // One row for all of them. Three servers configured and none answering used to draw
        // three notices with three Try again buttons on the search screen, and the notices
        // outnumbered the answers — ``SearchResultsView`` records that cost.
        let names = ["Attic NAS", "StoryArc Test Catalogue", "ada · 127.0.0.1"]
        let phrase = NeverReachedNotice.named(names)

        for name in names {
            #expect(phrase.contains(name), "\(name) is not in the notice.")
        }
        // One phrase, not three lines: a separator between the first two and a conjunction
        // before the last is what a list formatter produces and what a sentence needs.
        #expect(phrase.contains(","))
    }

    @Test("One unread library reads as a name, not a list")
    func one() {
        #expect(NeverReachedNotice.named(["Attic NAS"]) == "Attic NAS")
    }
}
