import Foundation
import Testing

@testable import LibraryFeature

/// Task 4.2: the app reads nothing from the browser it hands a reader to.
///
/// Two halves, because one alone would pass for the wrong reason. The first reads the
/// hand-off's own API and finds no channel data could come back through. The second reads
/// the source and finds no web view, no script and no capture — which is the edit a later
/// change would make, and the edit that would turn this feature into the thing App Store
/// guideline 5.2.3 forbids.
struct CoverSearchHandoffTests {
    /// The feature's own sources, found from this file rather than from the process
    /// directory: this repository nests agent worktrees, and a walk that climbs looking for
    /// a known folder climbs out of the checkout under test.
    private static func source(_ name: String) -> String {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Packages/StoryArcKit/Tests/LibraryFeatureTests/this file → StoryArcKit
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
    }

    /// The file's code, with its comments removed.
    ///
    /// The comments are where this file *explains* that it is not a `WKWebView`, so a scan
    /// that read them would refuse the very documentation the decision needs. The first
    /// version of this test did exactly that and failed on its own doc comment.
    private func code(of name: String) throws -> String {
        let path = Self.source(name)
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has \(name) moved? A guard that cannot find what it guards passes for ever."
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("//") ? "" : line
            }
            .joined(separator: "\n")
    }

    @MainActor
    @Test("The hand-off opens the address and receives nothing")
    func opensTheAddressAndReceivesNothing() throws {
        // The only closure the hand-off carries takes a URL and answers `Void`. There is no
        // parameter an image, a page, or a address-the-reader-ended-on could come back in.
        final class Opened: @unchecked Sendable {
            var url: URL?
        }
        let opened = Opened()
        let handoff = CoverSearchHandoff(
            title: "Fine Print", author: "Ada", open: { opened.url = $0 }
        )

        let destination = try #require(handoff.destination)
        handoff.open(destination)

        #expect(opened.url?.host() == "duckduckgo.com")
        #expect(opened.url?.query()?.contains("Fine%20Print") == true)
    }

    @MainActor
    @Test("No title means no hand-off")
    func refusesWithoutATitle() {
        let handoff = CoverSearchHandoff(title: " ", open: { _ in })
        #expect(handoff.destination == nil)
    }

    @Test("The hand-off is Safari, never a web view this app owns")
    func usesSafariRatherThanAWebView() throws {
        // `design.md` records the reason at length: an in-app web view that captures an
        // image is StoryArc performing the save guideline 5.2.3 forbids, and StoryArc's one
        // web view denies all network egress, so a second one with the opposite rule would
        // quietly undo that property.
        let text = try code(of: "CoverSearchHandoff.swift")
        #expect(text.contains("SFSafariViewController"))
        for forbidden in ["WKWebView", "WKUserScript", "WKUserContentController", "WebView("] {
            #expect(
                !text.contains(forbidden),
                "\(forbidden) is in the hand-off. The whole point of the hand-off is that it is not one."
            )
        }
    }

    @Test("Nothing in the hand-off captures, injects or reads the page")
    func capturesNothing() throws {
        let text = try code(of: "CoverSearchHandoff.swift")
        for forbidden in [
            "takeSnapshot", "snapshot(", "evaluateJavaScript", "SFSafariViewControllerDelegate",
            "ImageRenderer",
        ] {
            #expect(
                !text.contains(forbidden),
                "\(forbidden) is a way back from the browser into the app, and there is to be none."
            )
        }
    }
}
