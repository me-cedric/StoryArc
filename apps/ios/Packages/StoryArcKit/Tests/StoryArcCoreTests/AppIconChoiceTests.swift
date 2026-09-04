import Foundation
import Testing

@testable import StoryArcCore

/// The five faces, their asset names, and the reconciliation that makes the chooser able
/// to show what was *applied*.
///
/// Android's `AppIconChoiceTest` asserts the same table, plus the alias planner iOS has no
/// need for. The asset names are the load-bearing part: nothing in the compiler connects
/// `AppIcon-Paper` here to `AppIcon-Paper.appiconset` on disk, so this suite is the join.
@Suite("App icon faces")
struct AppIconChoiceTests {

    @Test("Five faces, in the order the chooser draws them")
    func faces() {
        #expect(AppIconChoice.allCases == [.ink, .paper, .bloom, .arc, .mono])
    }

    @Test("Ink is the default, and it is the only one that says so")
    func theDefault() {
        #expect(AppIconChoice.default == .ink)
        #expect(AppIconChoice.ink.isDefault)
        for face in AppIconChoice.allCases where face != .ink {
            #expect(!face.isDefault, "\(face) claims to be the default")
        }
    }

    /// The names `scripts/brand-mark.swift` writes into
    /// `apps/ios/App/Resources/Assets.xcassets`. Spelled out rather than derived, because a
    /// derivation would agree with itself after a rename and the catalogue would not.
    @Test("Each face names its own .appiconset")
    func assetNames() {
        #expect(AppIconChoice.ink.assetName == "AppIcon")
        #expect(AppIconChoice.paper.assetName == "AppIcon-Paper")
        #expect(AppIconChoice.bloom.assetName == "AppIcon-Bloom")
        #expect(AppIconChoice.arc.assetName == "AppIcon-Arc")
        #expect(AppIconChoice.mono.assetName == "AppIcon-Mono")
    }

    /// `nil` is UIKit's spelling of the primary icon, so the default face must map to it.
    /// Passing `"AppIcon"` to `setAlternateIconName` fails — the primary set is not one of
    /// the alternates the build declares.
    @Test("The default maps to nil, and every alternate to its own set")
    func alternateNames() {
        #expect(AppIconChoice.ink.alternateIconName == nil)
        for face in AppIconChoice.allCases where face != .ink {
            #expect(face.alternateIconName == face.assetName)
        }
    }

    /// The asset the chooser draws its tile from, which is **not** the `.appiconset`: an icon
    /// asset is not fetchable by name, so the mark's generator has to emit an ordinary imageset
    /// beside each icon set. Named here so the two sides cannot drift once it does — until then
    /// the tiles ship, and `ios-app-icon-chooser-ax5.png` shows all five drawn.
    @Test("Each face names the imageset a chooser tile needs")
    func tileResourceNames() {
        #expect(AppIconChoice.ink.tileResourceName == "AppIconTile-Ink")
        #expect(AppIconChoice.paper.tileResourceName == "AppIconTile-Paper")
        #expect(AppIconChoice.bloom.tileResourceName == "AppIconTile-Bloom")
        #expect(AppIconChoice.arc.tileResourceName == "AppIconTile-Arc")
        #expect(AppIconChoice.mono.tileResourceName == "AppIconTile-Mono")
        // Never the icon set's own name. Passing that to `UIImage(named:)` is the blank tile.
        for face in AppIconChoice.allCases {
            #expect(face.tileResourceName != face.assetName)
        }
    }

    @Test("Every alternate name round-trips back to its face")
    func reconcilesEveryFace() {
        for face in AppIconChoice.allCases {
            #expect(AppIconChoice(alternateIconName: face.alternateIconName) == face)
        }
    }

    /// A build that has dropped a face leaves a reader looking at the primary icon, so
    /// that is what an unknown name resolves to. Resolving to nothing would make the
    /// chooser mark no row at all on the one device that most needs it marked.
    @Test("An icon this build no longer ships reads as the default")
    func reconcilesAnUnknownName() {
        #expect(AppIconChoice(alternateIconName: "AppIcon-Sunset") == .default)
        #expect(AppIconChoice(alternateIconName: "") == .default)
    }

    /// The chooser stores nothing, but the type is `Codable` because a diagnostic and a
    /// what-changed note may name it. Asserted so the wire form cannot drift into
    /// something a future reader has to guess at.
    @Test("The wire form is the lower-case face name")
    func codable() throws {
        for face in AppIconChoice.allCases {
            let data = try JSONEncoder().encode(face)
            #expect(String(bytes: data, encoding: .utf8) == "\"\(face.rawValue)\"")
            #expect(try JSONDecoder().decode(AppIconChoice.self, from: data) == face)
        }
    }
}
