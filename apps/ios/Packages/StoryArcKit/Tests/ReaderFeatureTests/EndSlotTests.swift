import Foundation
import Testing

@testable import ReaderFeature

/// A swipe or a scroll past the last page reaches the end screen.
///
/// `comic-reader`: "a swipe or a scroll past the last page reaches the end screen". Before
/// this, only `turn(by:)` (a tap, a key, the slider) ever set `hasReachedEnd`; `TabView`
/// and `ScrollView` had nowhere further to go and simply resisted at the last page.
///
/// **Why it reads the source text**, the way `ReaderGestureTests` does for the same
/// reason: the rule lives inside a live `TabView` and a live `ScrollView`, neither of
/// which this host-run suite can drive. This is a tripwire, not a proof — it says the
/// wiring is there, never that a finger reached the end screen. Android's `EndSlotTest`
/// asserts the same table.
@Suite("Reaching the end by swipe or scroll")
struct EndSlotTests {

    private static let readerFeature: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReaderFeature")

    private func code(of name: String) throws -> String {
        let url = Self.readerFeature.appending(path: name)
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has \(name) moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("Slide gets one slot past the last page, to swipe into")
    func slideGetsAnEndSlot() throws {
        let containers = try code(of: "ReaderContainers.swift")
        #expect(
            containers.contains("Color.clear.tag(endSlot)"),
            """
            TabView no longer has an extra slot to swipe into. Without it a swipe past the \
            last page simply resists, the way it resists at the first.
            """
        )
    }

    @Test("Scroll gets one slot past the last page, to scroll into")
    func scrollGetsAnEndSlot() throws {
        let containers = try code(of: "ReaderContainers.swift")
        #expect(
            containers.contains(".id(endSlot)"),
            "The stitched scroll no longer has an extra slot past the last page."
        )
    }

    @Test("Reaching the extra slot opens the end screen")
    func reachingItOpensTheEndScreen() throws {
        let pages = try code(of: "ReaderPages.swift")
        #expect(
            pages.contains("guard new != endSlot else"),
            """
            Reaching the extra slot no longer opens the end screen. `comic-reader`: "a \
            swipe or a scroll past the last page reaches the end screen".
            """
        )
        #expect(pages.contains("hasReachedEnd = true"))
    }

    @Test("Left-to-right puts the end slot after the last page")
    func leftToRightEndsAfterTheRun() {
        #expect(endSlotPosition(slotCount: 5, isRightToLeft: false) == 5)
    }

    @Test("Right-to-left puts the end slot before the last page, not after page one")
    func rightToLeftEndsBeforeTheRun() {
        // Under right-to-left the last page is display position 0, so the slot past it
        // is -1. At `slotCount` it sat past page one, and a swipe back opened the end.
        #expect(endSlotPosition(slotCount: 5, isRightToLeft: true) == -1)
    }

    @Test("The containers put the end slot on the reading order's own side")
    func containersFollowTheDirection() throws {
        let containers = try code(of: "ReaderContainers.swift")
        // Slide, and both Scroll axes.
        #expect(containers.components(separatedBy: "withEndSlot(").count - 1 >= 3)
    }

    @Test("Going back off the end screen snaps off the extra slot")
    func goingBackSnapsOff() throws {
        // The end screen is built in one place since task 8.5 drew it under the curl too.
        let view = try code(of: "EndOfPublication.swift")
        #expect(
            view.contains("snapBackFromEndSlot()"),
            """
            Going back from the end screen no longer snaps off the extra slot. Left there, \
            the reader would find a blank page instead of the last one they read.
            """
        )
    }
}
