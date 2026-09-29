import Foundation
import Testing

@testable import ReaderFeature

/// A refused discrete turn gives a little and springs back (task 8.11, D13).
///
/// `page-transitions` "Turning at a boundary": "the page resists with a bounded rubber-band
/// and returns". The rule is asserted directly; the wiring is read from the source, because a
/// host-run `swift test` cannot watch an offset animate.
@Suite("A refused turn resists and returns")
struct RefusalResistanceTests {

    @Test("Left-to-right gives to the right, the way the missing page would push it")
    func leftToRightGivesRight() {
        let response = RefusalResponse.of(reduceMotion: false, isRightToLeft: false, scrolls: false)
        #expect(response == .nudge(RefusalResponse.reach))
    }

    @Test("Right-to-left gives to the left")
    func rightToLeftGivesLeft() {
        let response = RefusalResponse.of(reduceMotion: false, isRightToLeft: true, scrolls: false)
        #expect(response == .nudge(-RefusalResponse.reach))
    }

    @Test("Reduce Motion dims instead of moving the page")
    func reduceMotionDims() {
        #expect(RefusalResponse.of(reduceMotion: true, isRightToLeft: false, scrolls: false) == .dim)
    }

    @Test("A scroll shows nothing more than its own overscroll")
    func scrollIsLeftAlone() {
        #expect(RefusalResponse.of(reduceMotion: false, isRightToLeft: false, scrolls: true) == nil)
    }

    @Test("Every container plays the response on each refusal")
    func containerIsWired() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/ReaderFeature/ReaderPages.swift")
        let pages = try #require(try? String(contentsOf: url, encoding: .utf8))
        #expect(
            pages.contains(".modifier(RefusalResistance(\n                trigger: refusals,"),
            "The page container no longer plays the refusal response when a turn is refused."
        )
        #expect(pages.contains("scrolls: choices.effective.scrollAxis != nil"))
    }
}
