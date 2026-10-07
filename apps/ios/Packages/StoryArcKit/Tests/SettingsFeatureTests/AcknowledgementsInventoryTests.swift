import Foundation
import Testing

import StoryArcLicences

/// The acknowledgements inventory: what it decodes, and what it has to name.
///
/// `settings-and-about`, *Acknowledgements*: "every third-party library is listed with its
/// licence text". Two things were short of that. The decode required `platforms`, which
/// `scripts/notices.mjs` has always read as optional — so one entry written the way the
/// generator allows would have failed the decode of the whole file. And the inventory named
/// the two toolkits and the fonts, while the app also ships `SMBClient` and the eight packages
/// the Readium toolkit pins.
///
/// The screen itself is read as source rather than composed, for the reason `AboutBylineTests`
/// records: `swift test` runs on the host with no simulator, so this suite cannot compose
/// `AboutSettings` and read what it drew. Android composes its own `AboutGroup` in
/// `AboutContentsTest` and answers the drawing claim there.
@Suite("Acknowledgements inventory")
struct AcknowledgementsInventoryTests {

    /// The repository root, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk that climbs looking for a marker, for the reason
    /// `AboutBylineTests` records: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a climbing walk validates the parent checkout.
    private static let repositoryRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/SettingsFeatureTests/this file → the root
        for _ in 0..<7 { directory.deleteLastPathComponent() }
        return directory
    }()

    private static let inventoryPath = "packages/licences/notices.json"
    private static let viewPath =
        "apps/ios/Packages/StoryArcKit/Sources/SettingsFeature/AboutSettings.swift"
    private static let resolvedPath =
        "apps/ios/StoryArc.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

    /// One source's text. Missing is a failure rather than a skip, and it names the path it
    /// looked at: a guard that cannot find what it guards passes for ever after a rename.
    private func source(_ relativePath: String) throws -> String {
        let url = Self.repositoryRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    private func inventory() throws -> [Notice] {
        return try StoryArcLicences.apple(in: Data(try source(Self.inventoryPath).utf8))
    }

    /// Every entry, both platforms'.
    ///
    /// Read loosely rather than through ``StoryArcLicences/apple(in:)``, which filters: the
    /// directory is shared with Android and so are the texts, so a licence only Android names
    /// is still a file this package has to ship.
    private func everyEntry() throws -> [[String: Any]] {
        let data = Data(try source(Self.inventoryPath).utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the inventory is not a JSON object"
        )
        return try #require(root["notices"] as? [[String: Any]], "the inventory has no notices")
    }

    @Test("An entry that names no platform is listed on this one")
    func platformsIsOptional() throws {
        let entry = """
        { "notices": [ { "name": "Example", "licence": "MIT",
          "url": "https://example.invalid", "why": "A test entry." } ] }
        """
        let data = Data(entry.utf8)

        let listed = try StoryArcLicences.apple(in: data)

        #expect(
            listed.map(\.name) == ["Example"],
            """
            An entry with no platforms list was rejected, so this decode and
            scripts/notices.mjs disagree about the same file.
            """
        )
    }

    @Test("An inventory that does not decode throws rather than reading as empty")
    func aBrokenInventoryIsNotAnEmptyOne() throws {
        let data = Data(#"{ "notices": [ { "name": 7 } ] }"#.utf8)

        #expect(throws: (any Error).self) {
            try StoryArcLicences.apple(in: data)
        }
    }

    @Test("Every package the app resolves is acknowledged")
    func everyResolvedPackageIsListed() throws {
        let data = Data(try source(Self.resolvedPath).utf8)
        let resolved = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Package.resolved is not a JSON object"
        )
        let pins = try #require(resolved["pins"] as? [[String: Any]], "Package.resolved has no pins")
        let locations = pins.compactMap { $0["location"] as? String }
        // Nine: Readium and its eight. SMBClient is vendored under third_party and pinned by
        // no lockfile, so the next test names it instead.
        #expect(locations.count >= 9, "only \(locations.count) pins were read — has the format changed?")

        let listed = try inventory()
        for location in locations {
            // The repository address, without `.git`, is what an entry's `url` holds. Compared
            // on that rather than on the name: a pin's identity is lower-cased and a display
            // name is not, and two of these differ in case alone.
            let repository = location.replacingOccurrences(of: ".git", with: "")
            #expect(
                listed.contains { $0.url.caseInsensitiveCompare(repository) == .orderedSame },
                """
                \(repository) is resolved into the app and no entry names it, so the
                acknowledgements are short of a library the reader is running.
                """
            )
        }
    }

    @Test("Every listed component ships the licence text it names")
    func everyTextIsThere() throws {
        for entry in try everyEntry() {
            let name = entry["name"] as? String ?? "an unnamed entry"
            let licence = try #require(entry["licence"] as? String, "\(name) names no licence")
            let path = "packages/licences/texts/\(licence).txt"
            let url = Self.repositoryRoot.appendingPathComponent(path)
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(
                !body.isEmpty,
                """
                \(name) names the \(licence) licence and \(path) holds no text, so its row
                opens on a packaging-bug message.
                """
            )
        }
    }

    /// No component is LGPL, and the vendored SMB client keeps its own notice.
    ///
    /// `jcifs-ng` was the one LGPL entry, and ADR-0019 replaced it with `smbj`, which is
    /// Apache-2.0. The iOS client is vendored under `third_party/SMBClient`, so no lockfile
    /// names it: its row and its licence file are checked here instead.
    @Test("No component is LGPL, and the vendored SMB client carries its MIT notice")
    func noCopyleftAndTheVendoredClientIsAcknowledged() throws {
        let entries = try everyEntry()
        let lesser = entries.compactMap { entry -> String? in
            (entry["licence"] as? String)?.hasPrefix("LGPL") == true ? entry["name"] as? String : nil
        }
        #expect(lesser.isEmpty, "LGPL components are listed: \(lesser)")

        let smb = try #require(
            entries.first { $0["name"] as? String == "SMBClient" },
            "the vendored SMB client has no row, so the reader is running a library nobody names"
        )
        #expect(smb["licence"] as? String == "MIT")
        let copyright = try #require(smb["copyright"] as? String)
        let vendored = try source("third_party/SMBClient/LICENSE")
        #expect(vendored.contains(copyright), "the vendored LICENSE does not carry \(copyright)")
    }

    @Test("A build that cannot read its inventory says so instead of drawing nothing")
    func theScreenStatesAFailedRead() throws {
        let view = try source(Self.viewPath)

        #expect(
            view.contains("about.acknowledgements.unreadable"),
            """
            The About screen draws no sentence for a failed read, so the section is empty
            and silent — which reads as an app that ships nothing of anyone else's.
            """
        )
        #expect(
            !view.contains("= StoryArcLicences.forApple()"),
            """
            The screen still takes the inventory as a plain list, so it cannot tell a short
            inventory from an unreadable one.
            """
        )
    }
}
