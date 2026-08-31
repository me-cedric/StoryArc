import Foundation
import Testing

/// That fewer controls did not become fewer ways in.
///
/// `comic-reader`, *Fewer controls is not fewer ways in*:
///
/// > **WHEN** a user uses any gesture the reader supported before this change — edge tap,
/// > swipe, pinch, drag to zoom, or the mirrored equivalents in right-to-left mode
/// > **THEN** it behaves exactly as it did, because moving controls into a menu must not
/// > make the reader harder to drive
///
/// **This suite asserts the recognisers are still declared. It does not assert they fire.**
/// That distinction matters and is not a hedge: what it can catch is a gesture *deleted*
/// while the chrome was being cut down, which is the failure mode a declutter actually has.
/// What it cannot catch is a gesture that still exists and no longer works — for that the
/// reader has to be on a screen, and no gate in this repository puts it there.
///
/// The right-to-left assertion is the one worth reading twice. The mirroring is a single
/// expression in `ReaderNavigation.swift`, and `comic-reader` says the edge zones are
/// "mirrored in right-to-left mode" — which they are, for free, because the *pager's data*
/// is reversed rather than the zones. Deleting that reversal is a one-line edit that leaves
/// everything compiling and opens every manga at the wrong end.
@Suite("Every gesture the reader had, it still has")
struct ReaderGestureTests {

    /// The comic reader's sources, from this test's own compiled path. See
    /// `ReaderChromeTests` for why this is `#filePath`.
    private static let reader: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReaderFeature")

    private func code(of name: String) throws -> String {
        let url = Self.reader.appending(path: name)
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

    /// One gesture, and the one spelling in the source that answers it.
    ///
    /// A named type rather than a tuple, for the reason `large_tuple` gives.
    private struct Gesture {
        let what: String
        let file: String
        let spelling: String
    }

    /// Every gesture the reader answered before the chrome was cut down.
    private static let gestures: [Gesture] = [
        Gesture(
            what: "the pinch to zoom",
            file: "ZoomablePage.swift",
            spelling: "scrollView.maximumZoomScale"
        ),
        Gesture(
            what: "the drag to pan a zoomed page",
            file: "ZoomablePage.swift",
            spelling: "UIScrollViewDelegate"
        ),
        Gesture(
            what: "the double tap to zoom",
            file: "ZoomablePage.swift",
            spelling: "handleDoubleTap"
        ),
        Gesture(
            what: "the edge tap that turns a page",
            file: "ZoomablePage.swift",
            spelling: "edgeTap"
        ),
        Gesture(
            what: "the centre tap that reveals the chrome",
            file: "ZoomablePage.swift",
            spelling: "centreTap"
        ),
        Gesture(
            what: "the press that selects text in a PDF",
            file: "ZoomablePage.swift",
            spelling: "handleSelection"
        ),
        Gesture(
            what: "the swipe between pages",
            file: "ReaderContainers.swift",
            spelling: "TabView"
        ),
        Gesture(
            what: "the edge zones the tap routing shares with the page",
            file: "ReaderTurning.swift",
            spelling: "ZoomablePage.edgeZoneFraction"
        ),
        Gesture(
            what: "the centre tap toggling the chrome",
            file: "ReaderTurning.swift",
            spelling: "wantsChrome.toggle()"
        ),
        Gesture(
            what: "the right-to-left mirroring",
            file: "ReaderNavigation.swift",
            spelling: "isRightToLeft ? layout.count - 1 - displayIndex : displayIndex"
        ),
        Gesture(
            what: "the keyboard page turns",
            file: "ReaderView.swift",
            spelling: "onKeyPress"
        ),
    ]

    @Test("No gesture was lost when the chrome was cut to two controls")
    func everyGestureSurvives() throws {
        for gesture in Self.gestures {
            let code = try code(of: gesture.file)
            #expect(
                code.contains(gesture.spelling),
                """
                \(gesture.what) is gone from \(gesture.file) — `\(gesture.spelling)` is not \
                in it. `comic-reader` requires every gesture the reader supported before the \
                declutter to behave exactly as it did: "moving controls into a menu must not \
                make the reader harder to drive".
                """
            )
        }
    }
}
