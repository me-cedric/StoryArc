import Foundation
import Persistence
import Testing

@testable import StoryArc

/// The pointer rules of task 2.12: the click zones, on when nothing is stored, and the
/// three-second rest.
@Suite("Pointer reading")
struct PointerReadingTests {
    @Test("The zones are on when nothing is stored")
    func zonesOnByDefault() throws {
        let name = "mac-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = SettingsStore(defaults: defaults).settings()

        #expect(settings.turnPagesByTappingTheEdges)
        #expect(ClickZones.zone(atX: 10, width: 900, zonesOn: settings.turnPagesByTappingTheEdges) == .leading)
    }

    @Test("Each edge is a third of the width; the middle toggles the chrome")
    func thirds() {
        #expect(ClickZones.zone(atX: 299, width: 900, zonesOn: true) == .leading)
        #expect(ClickZones.zone(atX: 300, width: 900, zonesOn: true) == .middle)
        #expect(ClickZones.zone(atX: 600, width: 900, zonesOn: true) == .middle)
        #expect(ClickZones.zone(atX: 601, width: 900, zonesOn: true) == .trailing)
    }

    @Test("With the zones off every click is the middle")
    func zonesOff() {
        #expect(ClickZones.zone(atX: 10, width: 900, zonesOn: false) == .middle)
        #expect(ClickZones.zone(atX: 890, width: 900, zonesOn: false) == .middle)
    }

    @Test("A zone's step is mirrored right-to-left")
    func mirroredSteps() {
        #expect(ClickZones.step(for: .trailing, isRightToLeft: false) == 1)
        #expect(ClickZones.step(for: .leading, isRightToLeft: false) == -1)
        #expect(ClickZones.step(for: .trailing, isRightToLeft: true) == -1)
        #expect(ClickZones.step(for: .leading, isRightToLeft: true) == 1)
        #expect(ClickZones.step(for: .middle, isRightToLeft: true) == 0)
    }

    @Test("The chrome and the pointer hide after three seconds at rest")
    func threeSeconds() {
        #expect(PointerIdle.hideAfter == .seconds(3))
    }
}
