import Foundation
import Testing

@testable import ReaderFeature
import StoryArcCore

/// That both readers name their page turns and say where a turn landed.
///
/// `native-experience`, *Screen reader*:
///
/// > **AND** the reader announces the page number and total on each turn, and offers
/// > gestures to turn pages
///
/// Neither reader did. The comic reader contributed its container's own paging gesture, which
/// names a direction on screen rather than a page; Fast fade has no container and so offered
/// nothing at all; the reflowable reader is a web view and offered nothing either. No turn by
/// any means was announced.
///
/// The sentence is asserted directly. The wiring is read from the source — the trade
/// `TapZoneWiringTests` and `ReaderProgressTests` already make here, because a host-run
/// `swift test` has no VoiceOver to ask, and `StoryArcEpub` needs a simulator to build at all.
@Suite("A page turn is named and the arrival is announced")
struct PageTurnAccessibilityTests {

    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ relative: String) throws -> String {
        let url = Self.package.appending(path: relative)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("The announced position is the sentence each page already answers to")
    func theSentenceIsThePageLabel() {
        #expect(readerPositionSentence(page: 3, of: 20) == "Page 3 of 20")
        #expect(readerPositionSentence(page: 1, of: 1) == "Page 1 of 1")
    }

    @Test("Every comic transition mode carries the actions, Fast fade included")
    func theComicContainerCarriesTheActions() throws {
        let code = try source("Sources/ReaderFeature/ReaderPages.swift")

        #expect(
            code.contains("PageTurnAccessibility("),
            """
            `ReaderPages` applies no `PageTurnAccessibility`. It is the one place every \
            transition mode is wrapped — Slide, Curl, Fast fade and both scrolls — so a \
            modifier anywhere else leaves at least one mode with no page-turn action, which \
            is how Fast fade came to have none.
            """
        )
        for turn in ["turnInReadingOrder(by: 1)", "turnInReadingOrder(by: -1)"] {
            #expect(
                code.contains(turn),
                """
                The comic reader's page-turn action does not call `\(turn)`. Reading order is \
                what makes "next page" mean the next page to read in a right-to-left \
                publication, where the display order is reversed.
                """
            )
        }
    }

    @Test("The reflowable reader carries the actions, and announces off its own progression")
    func theReflowableReaderCarriesTheActions() throws {
        let tree = Self.package
            .deletingLastPathComponent()
            .appending(path: "StoryArcEpub/Sources/EpubReaderFeature")
        let view = try #require(
            try? String(contentsOf: tree.appending(path: "EpubReaderView.swift"), encoding: .utf8),
            "EpubReaderView.swift could not be read — has it moved?"
        )
        let progress = try #require(
            try? String(contentsOf: tree.appending(path: "EpubReaderProgress.swift"), encoding: .utf8),
            "EpubReaderProgress.swift could not be read — has it moved?"
        )

        #expect(
            view.contains("EpubPageTurnAccessibility("),
            """
            `EpubReaderView` applies no `EpubPageTurnAccessibility`, so VoiceOver walks the \
            publication's web view and is offered no way to turn a page, and no turn says \
            where it arrived.
            """
        )
        #expect(
            progress.contains("epubPositionSentence(position)") && !progress.contains("epub.progress"),
            """
            The reflowable reader's drawn line no longer comes from `epubPositionSentence`. \
            `ebook-reader` states the position "in words, in one line", and the announcement \
            speaks that same rule — a position phrased twice is two positions.
            """
        )
    }

    /// Task 26.7: the sentence took the device language, not the one chosen in the app.
    @Test("The page a turn landed on is announced in French on an English device")
    func arrivalFollowsTheChosenLanguage() {
        #expect(readerPositionSentence(page: 3, of: 12) == "Page 3 of 12")
        InterfaceLanguage.$scoped.withValue("fr") {
            #expect(readerPositionSentence(page: 3, of: 12) == "Page 3 sur 12")
        }
    }
}
