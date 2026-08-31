import Foundation
import Testing

/// A plain glass button is never tinted.
///
/// `.tint` on `.buttonStyle(.glass)` tints the **material**, not the glyph. Every chrome
/// control in this app was doing it, and the result was a row of opaque pills with no page
/// showing through them — which is what the owner saw and said did not look like the
/// platform's own floating controls. Photos, the example they gave, draws plain glass icon
/// buttons untinted beside one *prominent* tinted action.
///
/// **`DesignSystem/Glass.swift` had already written the rule down**, in two places:
/// "Untinted, deliberately: the spec wants the glass to pick up the page beneath it, and a
/// tint is precisely what stops it doing that", and "A fixed colour cannot sit on this
/// material, and one had been sitting on it" — a finding made on a device and then
/// reintroduced at five call sites that never used the helper carrying it. A rule written
/// in a doc comment protects the one file it is in.
///
/// `.glassProminent` is exempt and that is the point rather than an exception: it is the
/// filled, emphasised variant, it is *meant* to carry a tint, and the whole fix was moving
/// the controls that wanted a tint onto it.
///
/// **This reads source text.** Composing these views needs a simulator and `swift test` runs
/// on the host, which is the same trade `ReaderChromeTests` and `ReaderRoutingWiringTests`
/// make and explain. It cannot see a rendered pixel; it can see the modifier that made the
/// pixel wrong, which is the thing that regressed.
@Suite("Plain glass is untinted")
struct GlassIsUntintedTests {

    /// Every Swift source in the two reader packages, from this test's own compiled path.
    ///
    /// `#filePath` and not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy.
    private static let packages: [URL] = {
        let kit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ReaderFeatureTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StoryArcKit
        return [
            kit.appending(path: "Sources"),
            kit.deletingLastPathComponent().appending(path: "StoryArcEpub/Sources"),
        ]
    }()

    private static func swiftFiles() -> [URL] {
        packages.flatMap { root -> [URL] in
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { return [] }
            return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }

    @Test("No source finds a tint on a plain glass button")
    func plainGlassIsNeverTinted() throws {
        let files = Self.swiftFiles()
        #expect(files.count > 20, "the walk found almost nothing — has the layout moved?")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .map { $0.trimmingCharacters(in: .whitespaces) }

            for (index, line) in lines.enumerated() where line == ".buttonStyle(.glass)" {
                // The next code line. A tint two modifiers down still tints the material,
                // so this looks past whatever sits between them.
                let following = lines[(index + 1)...].prefix { !$0.hasPrefix(".buttonStyle(") }
                if following.contains(where: { $0.hasPrefix(".tint(") }) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            These tint a plain glass button, which tints the material and turns it opaque:
            \(offenders.joined(separator: ", "))
            A control that wants a tint wants `.buttonStyle(.glassProminent)`, which is the
            variant meant to carry one. A glyph that wants a colour wants `.foregroundStyle`.
            """
        )
    }

    /// The prominent variant is still in use, so the rule above cannot be satisfied by
    /// deleting every tinted control instead of moving it.
    @Test("The prominent variant is what carries a tint")
    func prominentGlassCarriesTheTint() throws {
        var tinted = 0
        for file in Self.swiftFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if text.contains(".glassProminent") && text.contains(".tint(") { tinted += 1 }
        }

        #expect(
            tinted > 0,
            """
            Nothing uses the tinted glass variant any more, which is how the rule above
            gets satisfied by removing emphasis rather than by placing it correctly.
            """
        )
    }
}
