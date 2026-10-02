import Foundation
import Testing

@testable import StoryArcCore

/// 19.7: every `.appiconset` carries a `dark` and a `tinted` appearance, so the system can
/// draw its own tinted icon instead of falling back to the one universal image every one of
/// the five committed `Contents.json` files held until now.
///
/// Reads the committed catalogue rather than calling the generator: `scripts/brand-mark.swift`
/// renders with CoreGraphics and ImageIO, which this host target cannot import, and `--check`
/// is itself the generator's own gate. What is worth asserting on the host is the shape of what
/// got committed — the same split `QuickActionWiringTests` makes for the App target's own
/// source, one step further down, onto generated JSON.
@Suite("App icon tinted and dark appearances")
struct AppIconTintedAppearanceTests {

    /// `apps/ios`, from this file rather than the working directory — see
    /// `QuickActionWiringTests` for why a worktree makes that the only safe way to find it.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func contents(of assetName: String) throws -> [String: Any] {
        let url = Self.appleRoot.appending(
            path: "App/Resources/Assets.xcassets/\(assetName).appiconset/Contents.json"
        )
        let data = try #require(
            try? Data(contentsOf: url),
            "\(url.path) is not readable — has \(assetName).appiconset moved?"
        )
        let parsed = try #require(
            try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(url.path) is not valid JSON"
        )
        return parsed
    }

    @Test(
        "Every face's Contents.json carries a dark and a tinted appearance",
        arguments: AppIconChoice.allCases
    )
    func everyFaceHasBothAppearances(face: AppIconChoice) throws {
        let images = try #require(
            try contents(of: face.assetName)["images"] as? [[String: Any]],
            "\(face.assetName).appiconset/Contents.json has no `images` array"
        )

        func appearance(_ image: [String: Any]) -> String? {
            let list = image["appearances"] as? [[String: Any]]
            return list?.first?["value"] as? String
        }

        #expect(
            images.contains { $0["appearances"] == nil },
            "\(face.assetName) no longer carries the plain, no-appearance image every OS below 18 draws"
        )
        let dark = images.first { appearance($0) == "dark" }
        let tinted = images.first { appearance($0) == "tinted" }
        #expect(dark != nil, "\(face.assetName) has no `dark` appearance entry")
        #expect(tinted != nil, "\(face.assetName) has no `tinted` appearance entry")

        // The same render answers both, per `Face.tintedFace`'s own doc comment — a reader
        // switching Appearance should not find the dark slot still drawing the full gradient.
        #expect(
            dark?["filename"] as? String == tinted?["filename"] as? String,
            "\(face.assetName)'s dark and tinted entries name different files"
        )

        let filename = try #require(
            tinted?["filename"] as? String, "\(face.assetName)'s tinted entry names no file"
        )
        let imageURL = Self.appleRoot.appending(
            path: "App/Resources/Assets.xcassets/\(face.assetName).appiconset/\(filename)"
        )
        #expect(
            FileManager.default.fileExists(atPath: imageURL.path),
            "\(face.assetName) names \(filename) for its dark/tinted appearance, and no such file is committed"
        )
    }
}
