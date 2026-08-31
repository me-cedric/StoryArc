import Foundation
import Testing

@testable import SettingsFeature

/// When the app tells a reader what changed, and when it says nothing at all.
///
/// `settings-and-about`: the screen is shown "once per version", "does not appear" on a
/// first ever launch, and a version with nothing worth saying "is still recorded as seen,
/// so the entry is not shown late alongside the next one".
///
/// Four scenarios, one rule: **the version is recorded at the moment the decision is
/// taken**, whichever way the decision goes. That is what makes the two silent branches
/// safe, and it is also the spec's clause about dismissal — "the seen flag is written when
/// the screen is shown, not when it is dismissed" — because a reader who swipes the sheet
/// away has still seen it, and nothing here is waiting for them to press anything.
///
/// Mirrored case for case by `WhatsNewTest.kt`.
@MainActor
@Suite("What's new")
struct WhatsNewTests {

    /// A defaults suite of its own, so one test cannot read what another wrote.
    private func store() throws -> WhatsNewStore {
        WhatsNewStore(defaults: try #require(UserDefaults(suiteName: "whatsnew-\(UUID().uuidString)")))
    }

    /// A log with one release in it, so the assertions do not move when the shipped log does.
    private let log = [
        WhatsNewRelease(
            version: "0.2.0",
            notes: [WhatsNewNote(symbolName: "book", title: "a", body: "b")]
        )
    ]

    @Test("a first ever launch shows nothing, and records the version anyway")
    func firstEverLaunch() throws {
        let store = try store()
        #expect(store.seenVersion == nil)

        let shown = WhatsNew.onLaunch(installed: "0.2.0", store: store, in: log)

        #expect(shown == nil, "Somebody who has never used the app has nothing to catch up on")
        #expect(
            store.seenVersion == "0.2.0",
            "The version is recorded even so, so the next update is the first thing they are told about"
        )
    }

    @Test("an update shows the release once")
    func anUpdateShowsItOnce() throws {
        let store = try store()
        store.record("0.1.0")

        let first = WhatsNew.onLaunch(installed: "0.2.0", store: store, in: log)
        #expect(first?.version == "0.2.0")

        let second = WhatsNew.onLaunch(installed: "0.2.0", store: store, in: log)
        #expect(second == nil, "Shown once per version, not once per launch")
    }

    @Test("a second launch at the same version shows nothing")
    func sameVersionAgain() throws {
        let store = try store()
        store.record("0.2.0")

        #expect(WhatsNew.onLaunch(installed: "0.2.0", store: store, in: log) == nil)
    }

    @Test("a version with nothing to say shows nothing and is still recorded")
    func nothingWorthSaying() throws {
        let store = try store()
        store.record("0.2.0")

        let shown = WhatsNew.onLaunch(installed: "0.3.0", store: store, in: log)

        #expect(shown == nil, "0.3.0 has no entry in this log")
        #expect(
            store.seenVersion == "0.3.0",
            "Recorded regardless, or 0.3.0's entry arrives late beside 0.4.0's"
        )
    }

    @Test("reaching the log from About changes nothing about what is seen")
    func aboutReadsTheLogAndNothingElse() throws {
        let store = try store()
        store.record("0.1.0")

        // What About shows is the whole log, and the log is a value with no store behind
        // it — reading it cannot write. `WhatsNewWiringTests` is the half of this claim
        // that a mutation can break; this half only proves the reading is possible.
        #expect(WhatsNew.releases.isEmpty == false)
        #expect(store.seenVersion == "0.1.0")
    }

    /// The ordering assertion below cannot fail while the log holds one release, so the
    /// comparator it uses is pinned here on fixtures instead. `0.10.0` against `0.9.0` is
    /// the case a string comparison gets wrong, and About lists these to a reader.
    @Test("a version is newer by its numbers, not by its letters")
    func versionsCompareAsNumbers() {
        #expect(WhatsNew.isNewer("0.10.0", "0.9.0"))
        #expect(WhatsNew.isNewer("1.0.0", "0.99.9"))
        #expect(WhatsNew.isNewer("0.2.1", "0.2.0"))
        #expect(WhatsNew.isNewer("0.2.0", "0.2.0") == false)
        #expect(WhatsNew.isNewer("0.9.0", "0.10.0") == false)
        // A shorter string is not automatically older: 0.2 and 0.2.0 are the same version.
        #expect(WhatsNew.isNewer("0.2", "0.2.0") == false)
        #expect(WhatsNew.isNewer("0.2.1", "0.2") )
    }

    @Test("the shipped log names releases newest first, and each version once")
    func theShippedLogIsOrdered() {
        let versions = WhatsNew.releases.map(\.version)
        #expect(Set(versions).count == versions.count, "A version appears twice: \(versions)")
        #expect(
            versions == versions.sorted(by: WhatsNew.isNewer),
            "About lists these in order, newest first. Found \(versions)"
        )
    }

    /// A release with no notes would present an empty sheet, and two notes sharing a symbol
    /// would give `ForEach` a duplicate identity — one row drawn, the other silently gone.
    @Test("every shipped release has notes, each under its own symbol")
    func everyReleaseHasDistinctNotes() {
        for release in WhatsNew.releases {
            #expect(release.notes.isEmpty == false, "\(release.version) has an empty note list")
            let symbols = release.notes.map(\.symbolName)
            #expect(symbols.allSatisfy { !$0.isEmpty }, "\(release.version) has a note with no symbol")
            #expect(Set(symbols).count == symbols.count, "\(release.version) repeats a symbol: \(symbols)")
        }
    }

    /// The screen is a handful of rows, not a commit log. Apple's own runs to four or five.
    @Test("no shipped release is a wall of text")
    func noReleaseIsCluttered() {
        for release in WhatsNew.releases {
            #expect(release.notes.count <= 5, "\(release.version) lists \(release.notes.count) notes")
        }
    }
}
