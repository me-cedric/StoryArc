import Foundation
import Testing

@testable import StoryArcCore

/// That the home-screen widget needs nothing but an Apple team to run on a device.
///
/// Owner answer O5. There is no Apple development team, so no device build can be signed with
/// the App Group the widget reads from. Everything else is in place, and these tests hold it:
/// one group, named the same in `ReadingSnapshot`, in `project.yml` and in all three
/// entitlement files; a widget target embedded in the app; a URL scheme for the widget's tap;
/// and a widget that reads the snapshot and nothing else (ADR-0011).
///
/// Files, not a build, for the reason `CarSimulatorOnlyTests` gives: this package cannot run
/// `xcodebuild`. `pnpm build:ios` is the build check, and it builds the widget.
@Suite("The widget waits only for signing")
struct WidgetSigningTests {

    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func text(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try #require(
            try? Data(contentsOf: Self.appleRoot.appendingPathComponent(relativePath)),
            "\(relativePath) could not be read — has it moved?"
        )
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any], "\(relativePath) is not a dictionary plist")
    }

    private static let groupKey = "com.apple.security.application-groups"

    private static let entitlementFiles = [
        "App/StoryArc.entitlements",
        "App/StoryArc.simulator.entitlements",
        "Widget/StoryArcWidget.entitlements",
    ]

    @Test("Every entitlement file names the snapshot's App Group", arguments: entitlementFiles)
    func everyFileNamesTheGroup(_ file: String) throws {
        #expect(
            try plist(file)[Self.groupKey] as? [String] == [ReadingSnapshot.appGroup],
            "\(file) does not name \(ReadingSnapshot.appGroup), so the app and the widget read different containers"
        )
    }

    @Test("project.yml declares the widget, embeds it, and names the same group")
    func projectDeclaresTheWidget() throws {
        let project = try text("project.yml")

        #expect(project.contains("  StoryArcWidget:\n    type: app-extension"), "no widget extension target")
        #expect(project.contains("- target: StoryArcWidget"), "the app does not embed the widget")
        #expect(project.contains("NSExtensionPointIdentifier: com.apple.widgetkit-extension"))
        #expect(project.contains("- \(ReadingSnapshot.appGroup)"), "project.yml names another group")
        #expect(
            project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.mecedric.storyarc.widget"),
            "the widget's bundle identifier is not a child of the app's, so no team could sign the pair"
        )
        #expect(
            project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]\": Widget/StoryArcWidget.entitlements"),
            "the simulator build of the widget takes the app's entitlements"
        )
    }

    @Test("The app answers the scheme the widget's tap opens")
    func theAppAnswersTheScheme() throws {
        let types = try #require(try plist("App/Info.plist")["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(ReadingSnapshot.urlScheme), "a widget tap would open nothing")
    }

    /// ADR-0011: the widget is a second process. It reads the snapshot, and a widget that
    /// reached for the progress store or a cover cache would read a container it cannot open.
    @Test("The widget reads the snapshot and nothing else")
    func theWidgetReadsOnlyTheSnapshot() throws {
        let sources = try ["Widget/StoryArcWidget.swift", "Widget/ReadingWidgetView.swift"].map(text)
        let widget = sources.joined(separator: "\n")

        #expect(widget.contains("ReadingSnapshotStore.shared()"), "the widget no longer reads the snapshot")
        for reach in ["ProgressStore", "LibraryCache", "CoverCache", "LibraryModel", "UserDefaults"] {
            #expect(!widget.contains(reach), "the widget reaches for \(reach), which only the app can open")
        }
        let imports = Set(widget.split(separator: "\n").filter { $0.hasPrefix("import ") })
        #expect(imports == ["import SwiftUI", "import WidgetKit", "import StoryArcCore"])
    }
}
