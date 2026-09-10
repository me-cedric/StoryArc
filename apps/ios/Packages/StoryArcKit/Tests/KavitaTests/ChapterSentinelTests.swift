import Testing

@testable import Kavita

/// That Kavita's no-number sentinel never leaves the model as a number.
///
/// **`-100000` is what Kavita writes for a chapter with no number at all** — a collected
/// edition, a volume with one part. A reader met it three times over: as a row in a
/// chapter list, as *Continue -100000*, and as the name a downloaded file was written
/// under. Each of those screens asked the question its own way, and the shelf had been
/// guarded while the others had not.
///
/// So the rule lives here, on the model every screen reads. Android's `ChapterSentinelTest`
/// asserts the same table against the same fields.
@Suite("A chapter's number, and the sentinel that is not one")
struct ChapterSentinelTests {

    private func chapter(_ number: String, title: String? = nil) -> KavitaChapter {
        KavitaChapter(id: 1, number: number, title: title)
    }

    @Test("A real number is a number")
    func aNumber() {
        #expect(chapter("43").issueNumber == "43")
        #expect(chapter("43").displayName == "43")
    }

    @Test("A decimal chapter is a number too, because half issues exist")
    func aDecimal() {
        #expect(chapter("1.5").issueNumber == "1.5")
    }

    @Test("The sentinel is not a number")
    func theSentinel() {
        #expect(chapter("-100000").issueNumber == nil)
    }

    @Test("Any negative is not a number, because none of them is an issue")
    func anyNegative() {
        #expect(chapter("-1").issueNumber == nil)
        #expect(chapter("-42").issueNumber == nil)
    }

    @Test("Nothing at all is not a number")
    func nothing() {
        #expect(chapter("").issueNumber == nil)
    }

    @Test("A title always wins, sentinel or not")
    func aTitleWins() {
        #expect(chapter("-100000", title: "The Long Halloween").displayName == "The Long Halloween")
        #expect(chapter("43", title: "Issue 43").displayName == "Issue 43")
    }

    @Test("An unnumbered chapter has no name of its own, and does not invent one")
    func noName() {
        // Empty rather than a made-up label: what to call it is the screen's decision, and
        // a screen has its own words for it — the chapter list says *Unnumbered*, which is
        // true, where this used to say "-100000", which is a database's private business.
        #expect(chapter("-100000").displayName.isEmpty)
        #expect(chapter("-100000", title: "").displayName.isEmpty)
    }
}
