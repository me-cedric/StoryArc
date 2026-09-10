import Foundation
import Testing

/// That the two shaders are the same shader.
///
/// `design.md` asks for one projection "expressed twice rather than solved twice", and
/// ``PageRollTests`` holds both platforms' *arithmetic* to one table of numbers. Neither
/// test process has a GPU in it, so nothing there reaches the shaders themselves — and a
/// shader that had drifted from the arithmetic would leave every suite green while the two
/// platforms drew different page turns.
///
/// **So this compares the two shader sources, line by line, on the expressions that carry
/// the model.** Metal spells the area `area` and AGSL spells it `size`, and Metal needs a
/// `y` local where AGSL reads `xy.y`; those two differences are normalised and every other
/// character has to match. The constants are not checked here because they cannot drift —
/// both shaders receive them as parameters read from `PageRoll`.
///
/// It is a tripwire, not a proof. `docs/designs/screenshots/` holds the frames that show
/// the same turn on both platforms, which is what a proof of this looks like.
@Suite("The two page-curl shaders agree")
struct PageCurlShaderTests {

    /// The repository root, found from this file rather than from the working directory.
    private static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/ReaderFeatureTests/this file → the root
        for _ in 0..<7 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.root.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    /// One shader's text, with the two spellings the platforms force normalised away.
    private func normalised(_ text: String) -> String {
        text
            .replacingOccurrences(of: "area.", with: "size.")
            .replacingOccurrences(of: "xy.y", with: "y")
            .replacingOccurrences(of: "xy.x", with: "x")
    }

    private func metal() throws -> String {
        normalised(try source("apps/ios/Packages/StoryArcKit/Sources/ReaderFeature/PageCurl.metal"))
    }

    private func agsl() throws -> String {
        normalised(
            try source(
                "apps/android/feature/reader/src/main/kotlin/app/storyarc/feature/reader/PageCurl.kt"
            )
        )
    }

    /// Every expression that carries the projection.
    ///
    /// Written once, asserted against both files. A change to the model is a change here
    /// and in both shaders, which is three edits — and that is the price of a projection
    /// two platforms have to agree on.
    private let model = [
        "float radius = max(radiusMax * size.x * sin(PI * progress), 0.0)",
        "float fold = size.x * (1.0 - progress) + lean * radius * (0.5 - y / size.y)",
        "float lipRim = fold + radius",
        "float beyond = (x - lipRim) / (size.x * shadow)",
        "1.0 - 0.45 * exp(-beyond * beyond)",
        "float across = clamp((x - fold) / radius, 0.0, 1.0)",
        "float angle = PI - asin(across)",
        "float lambert = -cos(angle)",
        "fold + radius * angle",
        "back * (rim + (1.0 - rim) * lambert)",
        "float edge = 2.0 * fold - size.x + PI * radius",
        "2.0 * fold - x + PI * radius",
        "float reach = away / (size.x * crease)",
        "exp(-reach * reach) * 0.5",
    ]

    @Test("Metal carries the whole projection")
    func metalCarriesIt() throws {
        let text = try metal()
        for line in model {
            #expect(text.contains(line), "PageCurl.metal no longer contains `\(line)`.")
        }
    }

    @Test("AGSL carries the whole projection")
    func agslCarriesIt() throws {
        let text = try agsl()
        for line in model {
            #expect(text.contains(line), "PageCurl.kt's AGSL no longer contains `\(line)`.")
        }
    }

    @Test("Both shaders branch in the same order")
    func theBranchOrderMatches() throws {
        // The order is load-bearing: the page beneath is answered first, then the lip, then
        // the sheet's free edge, then the flat back face. A shader that tested the flat
        // back face before the lip would draw the fold over the roll.
        let order = ["x > lipRim", "radius > 0.0 && x >= fold", "x < edge"]
        for text in [try metal(), try agsl()] {
            var searched = text.startIndex..<text.endIndex
            for branch in order {
                let found = try #require(
                    text.range(of: branch, range: searched),
                    "A shader no longer branches on `\(branch)`, or branches on it too early."
                )
                searched = found.upperBound..<text.endIndex
            }
        }
    }

    @Test("Neither shader keeps a constant of its own")
    func theConstantsComeFromOnePlace() throws {
        // `PageRoll` owns the numbers and both shaders receive them. A literal that looked
        // like one of them, written into a shader, is how the two platforms drift apart
        // while every test passes.
        for text in [try metal(), try agsl()] {
            for constant in ["0.04", "1.5", "0.35"] {
                #expect(
                    !text.contains(constant),
                    "A shader spells the constant \(constant) itself instead of taking it as a parameter from PageRoll."
                )
            }
        }
    }
}
