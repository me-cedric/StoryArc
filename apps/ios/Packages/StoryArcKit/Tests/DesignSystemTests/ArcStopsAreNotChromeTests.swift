import Foundation
import SwiftUI
import Testing

@testable import DesignSystem

/// The mark's later arc stops and the icon plate never reach the chrome.
///
/// `brand.arcMid`, `brand.arcLate`, `brand.arcEnd` and `brand.iconPlate` exist so the app
/// icon can be generated from tokens rather than from four hexes typed twice. They are
/// **identity**, not chrome: `design.md` §2 says colour is information and never
/// decoration, and a slider painted in the arc's third stop tells a reader nothing they
/// can act on. Four stops spread across tab bars and chips is the mark's gradient leaking
/// out of the icon it belongs to.
///
/// `brand.accent` and `brand.secondary` *are* chrome and are exempt — that is what they
/// are for, and `accentIsStillReachable` below is what stops this rule being satisfied by
/// banning the whole brand group.
///
/// **This reads source text.** The rule is about which token name appears in which
/// position, which is exactly what a compiler cannot object to: every one of these is a
/// `Color` and assigning any of them anywhere type-checks. It is the same trade
/// `GlassIsUntintedTests` makes and explains — it cannot see a rendered pixel, but it can
/// see the assignment that would make the pixel wrong.
///
/// Android's `ArcStopsAreNotChromeTest` is the mirror of this file and enforces the same
/// table over its own tree. Mirrored rather than written once, because each platform's own
/// gate has to fail for its own violation: `pnpm test:ios` would not notice a Kotlin one,
/// and `pnpm gradle :core:designsystem:testDebugUnitTest` is a documented gate on its own.
@Suite("The arc's stops are identity, not chrome")
struct ArcStopsAreNotChromeTests {

    /// The four identity tokens, named *and referenced*.
    ///
    /// The reference is the load-bearing half. A guard that only holds strings passes
    /// vacuously the day a token is renamed — it goes looking for a name nothing uses any
    /// more and finds nothing, which reads as success. Holding the real token beside its
    /// name means a rename breaks this file's **compile**, and the name it searches for
    /// cannot drift from the name it checked.
    private static let identityTokens: [(name: String, color: Color)] = [
        ("arcMid", StoryArcColor.Brand.arcMid),
        ("arcLate", StoryArcColor.Brand.arcLate),
        ("arcEnd", StoryArcColor.Brand.arcEnd),
        ("iconPlate", StoryArcColor.Brand.iconPlate),
    ]

    /// Files allowed to name an identity token: the brand surfaces.
    ///
    /// **Empty today, and that is the current truth rather than an oversight** — no screen
    /// draws the mark from tokens yet. The icon chooser of §5.3 is the one that will, and
    /// it belongs here by basename when it lands. `accentPositionRule` below still applies
    /// inside an allowed file, so being on this list buys the right to *draw* the brand,
    /// not the right to accent a control with it.
    private static let brandSurfaces: Set<String> = []

    /// Every Swift source the two packages and the app target hold.
    ///
    /// `#filePath` and not a walk up from the working directory, for the reason
    /// `GlassIsUntintedTests` gives: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker leaves the
    /// checkout under test and guards the parent's copy instead.
    private static let roots: [URL] = {
        let kit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DesignSystemTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StoryArcKit
        let packages = kit.deletingLastPathComponent()
        let ios = packages.deletingLastPathComponent()
        return [
            kit.appending(path: "Sources"),
            packages.appending(path: "StoryArcEpub/Sources"),
            ios.appending(path: "App"),
        ]
    }()

    /// Source files under one root, minus the generated tokens.
    ///
    /// `Generated/StoryArcTokens.swift` *declares* all four and must: it is emitted from
    /// `color.json` and is where the values live. A declaration is not a use, and a guard
    /// that cannot tell them apart fails on the one file that is allowed to be there.
    private static func swiftFiles(in root: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { !$0.pathComponents.contains("Generated") }
    }

    private static func swiftFiles() -> [URL] { roots.flatMap(swiftFiles(in:)) }

    /// A file's code lines, with `//` comments stripped.
    ///
    /// The prose above each token in this repository names the tokens it is talking about,
    /// so a guard that reads comments flags its own documentation.
    private static func codeLines(of file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
    }

    /// The walk reaches every root it claims to, checked **per root**.
    ///
    /// The first version of this guard asserted a total of more than twenty files, and a
    /// mutation showed that useless: pointing the largest root — `StoryArcKit/Sources`,
    /// 331 files — at a path that does not exist left the other two holding 56 between
    /// them, the total floor held, and **all three rules passed while guarding two thirds
    /// of the app**. A guard whose coverage check survives losing its main root is a guard
    /// that reports on whatever it happens to find.
    ///
    /// So each root is checked on its own, and the floors are per root rather than summed.
    /// They are deliberately far below today's counts — this catches a root that moved or
    /// was renamed, not a package that shrank.
    @Test("The walk reaches every root it claims to, and none of them is empty")
    func theWalkCoversWhatItClaims() {
        for root in Self.roots {
            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue,
                "not a directory: \(root.path) — has the layout moved?"
            )
            #expect(
                Self.swiftFiles(in: root).count >= 10,
                "almost no Swift sources under \(root.path) — has the layout moved?"
            )
        }
        #expect(Self.roots.count == 3, "a root was added or dropped without a floor for it")
    }

    @Test("No app source names an identity token outside a brand surface")
    func identityTokensStayOutOfTheApp() {
        let files = Self.swiftFiles()

        var offenders: [String] = []
        for file in files where !Self.brandSurfaces.contains(file.lastPathComponent) {
            for (index, line) in Self.codeLines(of: file).enumerated() {
                for token in Self.identityTokens where line.contains(".\(token.name)") {
                    offenders.append("\(file.lastPathComponent):\(index + 1) — \(token.name)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            These name one of the mark's identity tokens in app code:
            \(offenders.joined(separator: ", "))
            `arcMid`, `arcLate`, `arcEnd` and `iconPlate` belong to the mark, the app icons
            and brand surfaces. A control that wants the brand's colour wants
            `Palette.accent`; a second emphasis wants `StoryArcColor.Brand.secondary`. If
            this really is a brand surface drawing the mark, add its filename to
            `brandSurfaces` — and note the accent rule still applies inside it.
            """
        )
    }

    @Test("No identity token sits in an accent position, brand surface or not")
    func accentPositionRule() {
        // The durable half of the rule. The check above is absolute *today* because no
        // screen draws the mark yet; the moment one does and joins `brandSurfaces`, this
        // is what still holds inside it. A page may draw the arc and must not accent a
        // control with it.
        let positions = ["accent:", "accentMuted:", ".tint(", ".accentColor(", ".foregroundStyle("]

        var offenders: [String] = []
        for file in Self.swiftFiles() {
            for (index, line) in Self.codeLines(of: file).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard positions.contains(where: { trimmed.contains($0) }) else { continue }
                for token in Self.identityTokens where trimmed.contains(".\(token.name)") {
                    offenders.append("\(file.lastPathComponent):\(index + 1) — \(token.name)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            These put one of the mark's identity tokens in a chrome accent position:
            \(offenders.joined(separator: ", "))
            An accent is `Palette.accent`, which is one value on every appearance and is
            gated on both canvases. The arc's later stops are gated by nothing, because
            nothing is meant to be read against them.
            """
        )
    }

    @Test("The chrome accents are exempt, and the app actually uses them")
    func accentIsStillReachable() {
        // Without this, the two rules above are satisfied by an app that names no brand
        // token at all — which is how a guard ends up protecting an empty room. The same
        // reason `GlassIsUntintedTests` asserts the prominent variant is still in use.
        var usesAccent = 0
        for file in Self.swiftFiles() {
            let code = Self.codeLines(of: file).joined(separator: "\n")
            if code.contains("Brand.accent") || code.contains("Palette.accent")
                || code.contains(".accent") { usesAccent += 1 }
        }

        #expect(
            usesAccent > 0,
            """
            Nothing reaches the chrome accent any more, which is how the rules above get
            satisfied by removing the brand rather than by placing it correctly.
            """
        )

        // And the exemption is stated as a value, not only in prose: neither chrome token
        // is on the forbidden list.
        let forbidden = Set(Self.identityTokens.map(\.name))
        #expect(!forbidden.contains("accent"))
        #expect(!forbidden.contains("secondary"))
        #expect(!forbidden.contains("secondaryStrong"))
        #expect(!forbidden.contains("accentMuted"))
    }
}
