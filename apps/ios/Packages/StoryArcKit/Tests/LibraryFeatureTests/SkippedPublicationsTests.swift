import Foundation
import Testing

@testable import LibraryFeature

/// The rules behind the notice that replaced *"2 couldn't be opened"*.
///
/// Every one of these was true of nothing before: the toast had a count, a six-second timer
/// and no state, so there was nothing to assert about it beyond that it rendered. What is
/// asserted here is the whole substance of the replacement — which sentence a reader gets,
/// whether a set they dismissed comes back, and when an entry leaves the list.
///
/// Android asserts the same cases in `SkippedPublicationsTest`.
@Suite("Skipped publications")
struct SkippedPublicationsTests {

    private let sevenZip = SkippedPublications.Entry(
        name: "refused.cb7",
        reason: "CB7 is not a format StoryArc reads"
    )
    private let protected = SkippedPublications.Entry(
        name: "password-protected.cbz",
        reason: "the archive is password protected"
    )

    @Test("Nothing failed, nothing is said")
    func silentWhenNothingFailed() {
        #expect(SkippedPublications().notice == .nothing)
        // And a scan that met nothing does not leave a notice from the one before it.
        #expect(SkippedPublications().settling([sevenZip]).settling([]).notice == .nothing)
    }

    @Test("One failure names its publication and its reason")
    func oneIsNamed() {
        // The delta spec: "the notice names that publication and states the reason in the
        // words `publication-formats` gives for it". Not a count, and not a sentence this
        // layer wrote.
        let skipped = SkippedPublications().settling([sevenZip])
        #expect(skipped.notice == .one(name: "refused.cb7", reason: "CB7 is not a format StoryArc reads"))
    }

    @Test("Several state the count and keep every reason apart")
    func severalKeepTheirOwnReasons() {
        let skipped = SkippedPublications().settling([sevenZip, protected])

        #expect(skipped.notice == .several(count: 2))
        // "the reasons are not merged: two files that failed differently say different
        // things". The count is the notice; the reasons are the list behind it.
        #expect(skipped.entries.map(\.name) == ["refused.cb7", "password-protected.cbz"])
        #expect(Set(skipped.entries.map(\.reason)).count == 2)
    }

    @Test("Dismissal is the reader's, and the list stays reachable")
    func dismissalKeepsTheList() {
        let skipped = SkippedPublications().settling([sevenZip, protected]).dismissing()

        // Not `.nothing`: the notice has gone and the way to the list has not.
        #expect(skipped.notice == .reachable)
        #expect(skipped.entries.count == 2)
    }

    @Test("The same set does not announce itself twice")
    func sameSetDoesNotReturn() {
        let dismissed = SkippedPublications().settling([sevenZip, protected]).dismissing()

        // A second scan of the same library meets the same two files. Nothing changed, so
        // there is nothing to say again — the toast's own failure was announcing anyway.
        #expect(dismissed.settling([sevenZip, protected]).notice == .reachable)
        // Order is not the set. The same two files met the other way round are still the
        // same two files.
        #expect(dismissed.settling([protected, sevenZip]).notice == .reachable)
    }

    @Test("A set that grows announces itself again")
    func aNewFailureIsNews() {
        let dismissed = SkippedPublications().settling([sevenZip]).dismissing()
        let alsoProtected = dismissed.settling([sevenZip, protected])

        // "the count is not shown again for the same publications **unless the set
        // changes**". It changed.
        #expect(alsoProtected.notice == .several(count: 2))
    }

    @Test("A publication that later opens leaves the list without being dismissed")
    func fixedPublicationLeaves() {
        let both = SkippedPublications().settling([sevenZip, protected])
        // The archive was re-downloaded unprotected, so the next walk does not report it.
        let one = both.settling([sevenZip])

        #expect(one.entries.map(\.name) == ["refused.cb7"])
        #expect(one.notice == .one(name: sevenZip.name, reason: sevenZip.reason))
    }

    @Test("The notice goes when the list empties")
    func emptyListEndsTheNotice() {
        let both = SkippedPublications().settling([sevenZip, protected])
        // Both fixed. Without this the list becomes a record of problems that were solved
        // weeks ago, and a reader learns to ignore it — which is the toast's failure
        // arrived at slowly.
        #expect(both.settling([]).notice == .nothing)
        #expect(both.settling([]).entries.isEmpty)
    }

    @Test("A publication fixed and then broken again is news a second time")
    func brokenAgainIsNews() {
        let dismissed = SkippedPublications().settling([sevenZip]).dismissing()
        // Gone from the list, so the acknowledgement goes with it: keeping it would make a
        // file that broke a second time silent for ever.
        let fixed = dismissed.settling([])
        #expect(fixed.settling([sevenZip]).notice == .one(name: sevenZip.name, reason: sevenZip.reason))
    }

    @Test("One file met twice in one scan is one row")
    func metTwiceIsOneRow() {
        // A remembered publication that also lives inside a picked folder is walked both
        // ways, and "2 couldn't be opened" for one file is worse than the count it replaced.
        let skipped = SkippedPublications().settling([sevenZip, sevenZip])
        #expect(skipped.entries.count == 1)
        #expect(skipped.notice == .one(name: sevenZip.name, reason: sevenZip.reason))
    }
}
