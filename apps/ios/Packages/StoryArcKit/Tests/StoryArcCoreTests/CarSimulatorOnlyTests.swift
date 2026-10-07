import Foundation
import Testing

/// That the CarPlay scene is switched on for the simulator build and for no other.
///
/// Task 12.6, owner answer O13. This project has no Apple development team, so a device build
/// that asks for `com.apple.developer.carplay-audio` cannot be signed. The simulator build
/// carries the entitlement and the scene manifest so the CarPlay Simulator can prove the scene.
/// Every other build carries neither.
///
/// Files, not a build: this package cannot run `xcodebuild`. `xcodebuild -showBuildSettings
/// -sdk iphoneos` and `-sdk iphonesimulator` answer which file each SDK takes, and the task
/// record names that run. These tests hold what a host can: the two committed files per side
/// and the two settings in `project.yml` that choose between them.
@Suite("CarPlay switches on for the simulator only")
struct CarSimulatorOnlyTests {

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

    private static let carEntitlement = "com.apple.developer.carplay-audio"
    private static let manifestKey = "UIApplicationSceneManifest"

    @Test("The device entitlements and Info.plist hold no car key")
    func theDeviceBuildCarriesNeither() throws {
        #expect(
            try plist("App/StoryArc.entitlements")[Self.carEntitlement] == nil,
            "the device entitlements ask for CarPlay, which no team can grant yet"
        )
        #expect(
            try plist("App/Info.plist")[Self.manifestKey] == nil,
            "Info.plist declares a scene manifest, so the device build carries the car scene"
        )
    }

    @Test("The simulator entitlements add the CarPlay key and change nothing else")
    func theSimulatorEntitlementsAddOnlyTheCarKey() throws {
        var expected = try plist("App/StoryArc.entitlements")
        let simulator = try plist("App/StoryArc.simulator.entitlements")

        #expect(simulator[Self.carEntitlement] as? Bool == true, "the simulator build does not ask for CarPlay")
        expected[Self.carEntitlement] = true
        #expect(
            NSDictionary(dictionary: expected).isEqual(to: simulator),
            "the two entitlement files differ in more than the car key"
        )
    }

    @Test("The simulator Info.plist is Info.plist plus a manifest with both roles")
    func theSimulatorPlistAddsTheManifest() throws {
        var simulator = try plist("App/Info.simulator.plist")
        let manifest = try #require(
            simulator[Self.manifestKey] as? [String: Any],
            "Info.simulator.plist has no scene manifest — run xcodegen generate"
        )
        let roles = try #require(manifest["UISceneConfigurations"] as? [String: Any])

        // A manifest replaces the system default, so one that names only the car role gives
        // the app no window. `design.md`, "The day an Apple team exists", step 3.
        #expect(roles["UIWindowSceneSessionRoleApplication"] != nil, "the phone's window role is missing")
        let car = try #require(roles["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]])
        #expect(
            car.first?["UISceneDelegateClassName"] as? String == "$(PRODUCT_MODULE_NAME).CarSceneDelegate",
            "the car role does not name CarSceneDelegate"
        )

        simulator[Self.manifestKey] = nil
        #expect(
            NSDictionary(dictionary: simulator).isEqual(to: try plist("App/Info.plist")),
            "Info.simulator.plist differs from Info.plist in more than the manifest — run xcodegen generate"
        )
    }

    @Test("project.yml chooses the simulator files by SDK, and names no device override")
    func theSettingsChooseBySdk() throws {
        let project = try text("project.yml")

        #expect(
            project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]\": App/StoryArc.simulator.entitlements")
        )
        #expect(project.contains("\"INFOPLIST_FILE[sdk=iphonesimulator*]\": App/Info.simulator.plist"))
        #expect(project.contains("plutil -insert UIApplicationSceneManifest"), "nothing writes Info.simulator.plist")
        #expect(
            !project.contains("[sdk=iphoneos"),
            "a device-only override exists; the car keys must reach no device build"
        )
        #expect(
            !project.contains(Self.carEntitlement),
            "project.yml names the CarPlay entitlement directly, which every SDK would take"
        )
    }
}
