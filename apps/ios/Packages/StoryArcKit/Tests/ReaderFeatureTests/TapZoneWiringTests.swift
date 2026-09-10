import Foundation
import Testing

/// That the tap-zone setting is read where a `@Environment` value can still be read.
///
/// **This exists because the setting did nothing on a device while every suite was green.**
/// `ReaderTapZonesTests` asserts the rule and passes whatever the reader does, because it
/// calls the rule. The reader called it from a closure held by a `UITapGestureRecognizer`,
/// and a `@Environment` property read outside a body pass gives back its *default* — which
/// for this one is `true`. So a reader who turned the zones off still turned pages by
/// tapping. Found on a simulator, by turning them off and tapping the side of a page.
///
/// The fix is that `tapHandler` reads the flag during the body pass and captures the `Bool`,
/// and `handleTap` takes it as a parameter. Nothing in the type system holds that: a later
/// edit can put `tapTurnsPages` back inside a closure and every test here stays green
/// unless it is this one. So this reads source text, for the reason `WhatsNewWiringTests`
/// sets out — the wiring is the claim, and no value can be asserted for it.
///
/// It is a tripwire, not a proof. `docs/designs/screenshots/a-third-turns-the-page-2026-09-10/`
/// holds the frames that are the proof.
@Suite("The tap-zone setting is read in a body pass")
struct TapZoneWiringTests {

    /// `apps/ios`, found from this file rather than from the working directory, because this
    /// repository nests agent worktrees and a walk upwards leaves the checkout under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/ReaderFeatureTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    private func containers() throws -> String {
        try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderContainers.swift")
    }

    @Test("The flag is a parameter, so it cannot be read late")
    func theFlagIsAParameter() throws {
        let turning = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderTurning.swift")

        #expect(
            turning.contains("func handleTap(at location: CGPoint, in size: CGSize, turns: Bool)"),
            """
            handleTap no longer takes the setting. If it reads `tapTurnsPages` itself, every
            caller is a gesture closure and the read lands outside the body pass.
            """
        )
        #expect(
            turning.contains("let turns = tapTurnsPages"),
            "tapHandler no longer reads the setting into a local, so nothing captures it."
        )
    }

    @Test("Every container routes its taps through the handler that carries the flag")
    func everyContainerUsesTheHandler() throws {
        let text = try containers()

        #expect(
            !text.contains("handleTap("),
            """
            A container calls handleTap directly again. The call is inside an escaping
            closure, so the flag it reads is the default and the setting stops working.
            Route it through tapHandler(), which reads the flag in the body pass.
            """
        )
        #expect(
            text.components(separatedBy: "tapHandler").count - 1 >= 4,
            """
            A container stopped using tapHandler. There are four tap routes — curl, single
            page, each half of a spread, and the stitched scroll — and each needs it.
            """
        )
    }
}
