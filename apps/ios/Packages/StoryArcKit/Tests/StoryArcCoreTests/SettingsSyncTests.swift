import Foundation
import Testing
@testable import StoryArcCore

/// `library-sync` task 3.5: settings and themes merge last-writer-wins per field. Android's
/// `SettingsSyncTest` makes the same claims.
struct SettingsSyncTests {

    /// The reader's own change to a setting, stamped as `SettingsStore` stamps it.
    private func setting(_ device: SyncDevice, at second: TimeInterval, _ edit: (inout AppSettings) -> Void) {
        var after = device.library.settings
        edit(&after)
        device.library.settingsChangedAt = ChangeStamps.restamped(
            changed: SettingsStamps.changed(from: device.library.settings, to: after),
            before: device.library.settingsChangedAt, after: device.library.settingsChangedAt,
            now: moment(second)
        )
        device.library.settings = after
    }

    /// The reader's own change to a theme, stamped as `ReaderPreferences` stamps it.
    private func theme(_ device: SyncDevice, at second: TimeInterval, _ edit: (inout ShelfSettings) -> Void) {
        let themes = device.library.themes
        var settings = themes.default(for: .reflowable)
        edit(&settings)
        let after = themes.settingDefault(settings, for: .reflowable)
        device.library.themesChangedAt = ChangeStamps.restamped(
            changed: ThemeStamps.changed(from: themes, to: after),
            before: device.library.themesChangedAt, after: device.library.themesChangedAt,
            now: moment(second)
        )
        device.library.themes = after
    }

    private func reflowable(_ device: SyncDevice) -> ShelfSettings {
        device.library.themes.default(for: .reflowable)
    }

    @Test func oneDevicesThemeAndAnotherDevicesFontSizeBothSurvive() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        setting(deviceA, at: 1) { $0.appearance = .dark }
        theme(deviceA, at: 2) { $0.theme.preset = .quiet }
        theme(deviceB, at: 3) { $0.values.fontSize = .large }

        try await deviceA.sync(place, at: 4)
        try await deviceB.sync(place, at: 5)
        try await deviceA.sync(place, at: 6)

        for device in [deviceA, deviceB] {
            #expect(device.library.settings.appearance == .dark)
            #expect(reflowable(device).theme.preset == .quiet)
            #expect(reflowable(device).values.fontSize == .large)
        }
    }

    @Test func theSameFieldChangedOnBothDevicesTakesTheLaterChange() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        setting(deviceA, at: 3) { $0.appearance = .dark }
        setting(deviceB, at: 2) { $0.appearance = .light }

        // B's older change is written first, and A's later one still wins: the moment decides,
        // not the order.
        try await deviceB.sync(place, at: 4)
        try await deviceA.sync(place, at: 5)
        try await deviceB.sync(place, at: 6)

        #expect(deviceA.library.settings.appearance == .dark)
        #expect(deviceB.library.settings.appearance == .dark)
        let stamp = try place.document().library.settings.changed?["appearance"]
        #expect(stamp == DocumentStamp(at: moment(3), by: "device-a"))
    }

    @Test func aSettingTheDocumentDoesNotCarryIsKept() {
        var local = AppSettings()
        local.lookUpMissingCovers = true

        let merged = SettingsStamps.merging(local, stamps: [:], with: DocumentSettings(), device: "device-a").value

        #expect(merged.lookUpMissingCovers)
    }

    @Test func aFieldOnlyAndroidHasIsReadAndLeftAlone() throws {
        // What Android writes: a field this platform cannot express, with the newest moment.
        let json = #"{"appearance":"dark","turnPagesWithVolumeButtons":true,"#
            + #""changed":{"turnPagesWithVolumeButtons":{"at":"2026-01-01T00:00:09Z","by":"device-b"},"#
            + #""appearance":{"at":"2026-01-01T00:00:09Z","by":"device-b"}}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remote = try decoder.decode(DocumentSettings.self, from: Data(json.utf8))

        let merged = SettingsStamps.merging(AppSettings(), stamps: [:], with: remote, device: "device-a")

        #expect(merged.value.appearance == .dark)
        #expect(merged.changedAt.keys.sorted() == ["appearance"])
    }

    @Test func aStoreStampsOnlyWhatTheReaderChangedAndKeepsAMomentAMergeBrought() {
        var french = AppSettings()
        french.language = "fr"
        let changed = ChangeStamps.restamped(
            changed: SettingsStamps.changed(from: AppSettings(), to: french), before: [:], after: [:], now: moment(7)
        )
        #expect(changed == ["language": moment(7)])

        let merged = ChangeStamps.restamped(
            changed: SettingsStamps.changed(from: AppSettings(), to: french),
            before: [:], after: ["language": moment(3)], now: moment(8)
        )
        #expect(merged == ["language": moment(3)])
    }
}
