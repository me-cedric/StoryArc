import Foundation
import Testing

/// That the finished surface states what could not be played.
///
/// Task 2.5, owner answer O12. ``PlayerCentre/unreadableAtEnd`` holds the count past the
/// teardown (`PlayerLastFinishedTests`), and a SwiftUI body cannot be read from a host test.
/// What this holds is the wire between the two, as source text, the way `ShellWiringTests`
/// does where no app test target exists: a count the centre keeps and the offer never draws
/// is a surface that says nothing. `PlayerDamageTests` in `UITests` walks it on a simulator,
/// over `truncated.m4b`.
@Suite("The finished player states the loss")
struct PlayerFinishedDamageTests {

    private static let sources: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/StoryArcKit/Tests/PlayerFeatureTests/this file → StoryArcKit
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("Sources/PlayerFeature")
    }()

    private func source(_ name: String) throws -> String {
        let url = Self.sources.appendingPathComponent(name)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("The full player hands the finished offer the count the centre kept")
    func theCountIsPassed() throws {
        let player = try source("FullPlayerView.swift")

        #expect(
            player.contains("unreadableParts: centre.unreadableAtEnd"),
            "the finished offer is built without the count, so a failed book ends in silence"
        )
    }

    @Test("The finished offer draws that count in words")
    func theCountIsDrawn() throws {
        let offer = try source("PlayerFinishedOffer.swift")

        #expect(
            offer.contains("PlayerText.damage(unreadableParts: unreadableParts)"),
            "the finished offer no longer draws the count it is given"
        )
    }
}
