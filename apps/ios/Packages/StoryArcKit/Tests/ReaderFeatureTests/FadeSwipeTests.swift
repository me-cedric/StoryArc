import Foundation
import Testing

@testable import ReaderFeature

/// Fast fade turns on a horizontal swipe (task 8.2).
///
/// `page-transitions` "Turning the tap zones off": "every other trigger still turns pages —
/// swipe, keyboard, controller". Fast fade has no container, so before this a reader with
/// the tap zones off could turn only by the slider. The rule is asserted directly; the
/// wiring is read from the source, the trade `TapZoneWiringTests` makes, because a
/// host-run `swift test` has no touch screen and no `UIScrollView`.
@Suite("Fast fade turns on a swipe")
struct FadeSwipeTests {

    @Test("A finger moving left asks for the next display position")
    func leftIsNext() {
        #expect(fadeSwipeStep(travel: -fadeSwipeThreshold) == 1)
        #expect(fadeSwipeStep(travel: -200) == 1)
    }

    @Test("A finger moving right asks for the previous display position")
    func rightIsPrevious() {
        #expect(fadeSwipeStep(travel: fadeSwipeThreshold) == -1)
    }

    @Test("A short drag turns nothing")
    func shortDragIsNoTurn() {
        #expect(fadeSwipeStep(travel: fadeSwipeThreshold - 1) == 0)
        #expect(fadeSwipeStep(travel: -(fadeSwipeThreshold - 1)) == 0)
    }

    private static let sources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReaderFeature")

    private func source(_ name: String) throws -> String {
        let url = Self.sources.appending(path: name)
        return try #require(try? String(contentsOf: url, encoding: .utf8), "\(name) could not be read")
    }

    @Test("Only Fast fade hands its pages a swipe, and the page installs it")
    func swipeIsWired() throws {
        let containers = try source("ReaderContainers.swift")
        #expect(
            containers.ranges(of: ".environment(\\.swipeTurn").count == 1,
            "Exactly one container, Fast fade, hands its pages a swipe. Slide and Curl own theirs."
        )
        let opening = try #require(containers.range(of: "var faded: some View {"))
        let rest = containers[opening.upperBound...]
        let faded = rest[..<(rest.range(of: "\n    }")?.lowerBound ?? rest.endIndex)]
        #expect(
            faded.contains(".environment(\\.swipeTurn, SwipeTurn { turn(by: $0) })"),
            "Fast fade no longer hands its pages a swipe that turns by one display step."
        )

        let zoomable = try source("ZoomablePage.swift")
        #expect(zoomable.contains("onSwipe: onSwipe"), "ZoomablePage no longer passes the swipe on.")
        #expect(zoomable.contains("addSwipe(to: scrollView, coordinator: context.coordinator)"))
        #expect(zoomable.contains("context.coordinator.onSwipe = onSwipe"))

        let swipeFile = try source("ZoomablePageSwipe.swift")
        #expect(swipeFile.contains("fadeSwipeStep(travel: recogniser.translation(in: view).x)"))
        #expect(swipeFile.contains("return !hasSlack && abs(velocity.x) > abs(velocity.y)"))

        let page = try source("ReaderPage.swift")
        #expect(page.contains("isEnabled: onSwipe != nil"), "A loading page no longer turns on a swipe.")
    }
}
