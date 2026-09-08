import Foundation
import Testing

/// That the car scene exists and that something routes a car to it.
///
/// **Review found both unguarded.** `App/CarScene.swift` could be deleted whole and every
/// test still passed, and so could the branch in `OrientationDelegate` that hands a car scene
/// its delegate. The rows a car draws are asserted by `CarShelfTests`; nothing asserted that
/// anything turns those rows into a template, or that a car reaches the code which does.
///
/// **Source text, and that is the second choice**, for the reason `ShellWiringTests` records:
/// `apps/ios/project.yml` declares no app unit-test target, so nothing in this package can
/// construct a scene delegate. It is a tripwire, not a proof — it asserts the wiring is
/// written, never that a car drew a list. Task 12.6 is the proof, and it needs an Apple
/// development team this project does not have.
@Suite("Car scene wiring")
struct CarSceneWiringTests {

    /// `apps/ios`, from this file rather than the working directory: this repository nests
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs out validates the
    /// parent checkout instead of the one under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
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

    @Test("A car scene is routed to the delegate that draws a list")
    func aCarSceneIsRouted() throws {
        let orientation = try source("App/OrientationDelegate.swift")

        #expect(
            orientation.contains("connectingSceneSession.role == .carTemplateApplication"),
            "nothing tells a car scene apart from the phone's, so a car gets the phone's delegate"
        )
        #expect(
            orientation.contains("CarSceneDelegate.self"),
            "the car scene is no longer routed to CarSceneDelegate"
        )
    }

    @Test("The scene delegate turns the shelf's rows into a car template")
    func theSceneDrawsTheRows() throws {
        let scene = try source("App/CarScene.swift")

        #expect(scene.contains("CarShelf.rows"), "the scene no longer asks CarShelf for its rows")
        #expect(scene.contains("CPListTemplate"), "the scene no longer builds a list template")
        #expect(
            scene.contains("CPNowPlayingTemplate"),
            "choosing a row no longer reaches the now-playing template"
        )
    }

    @Test("The car file compiles without the entitlement this project cannot have")
    func theCarFileIsGuarded() throws {
        let scene = try source("App/CarScene.swift")

        // `import CarPlay` needs no entitlement and the framework ships in the SDK, but the
        // guard keeps the file honest if the module ever stops resolving. ADR-0011 records
        // what an unprovisionable capability did to a build here.
        #expect(
            scene.contains("#if canImport(CarPlay)"),
            "the car file is no longer guarded, so a toolchain without CarPlay breaks the build"
        )
    }
}
