import Foundation
import Testing

@testable import Persistence

/// What the app remembers about how fast a listener wants a book read.
///
/// `audio-playback`: the speed "is remembered for that publication and offered as the default
/// for others in the same series".
///
/// A private `UserDefaults` suite rather than a mock, for the reason `LibraryPreferencesTests`
/// gives: what is being asserted is that the values actually round-trip through storage.
///
/// **The mirror of Android's `PlaybackPreferencesTest`, case for case.** Two scopes resolved
/// publication-then-series is a rule, not an implementation detail, and a platform that
/// resolved them the other way round would reach back and change volume one when a listener
/// slowed volume two down.
@Suite("Playback preferences")
struct PlaybackPreferencesTests {

    /// A private defaults suite, and the means to throw it away afterwards.
    private struct Store {
        let preferences: PlaybackPreferences
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Store {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Store(preferences: PlaybackPreferences(defaults: defaults), defaults: defaults, name: name)
    }

    @Test("A publication nobody has set starts at the narrator's own speed")
    func untouchedIsNormal() throws {
        let store = try fresh()
        defer { store.discard() }

        #expect(store.preferences.speed(of: "sea-room", series: "Sea Room") == 1)
    }

    @Test("A speed comes back for the publication it was set on")
    func itComesBack() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(1.4, of: "sea-room-1", series: "Sea Room")

        #expect(store.preferences.speed(of: "sea-room-1", series: "Sea Room") == 1.4)
    }

    /// What makes a series a *default* rather than a second setting: a listener who settles on
    /// 1.4× for volume one has said something about the narrator, not about that file.
    @Test("The rest of the series is offered it")
    func theSeriesIsOfferedIt() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(1.4, of: "sea-room-1", series: "Sea Room")

        #expect(store.preferences.speed(of: "sea-room-2", series: "Sea Room") == 1.4)
    }

    /// The publication's own choice wins, and adjusting one book does not reach back.
    @Test("A publication's own speed wins over the series default")
    func ownWinsOverTheSeries() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(1.4, of: "sea-room-1", series: "Sea Room")
        store.preferences.remember(0.9, of: "sea-room-2", series: "Sea Room")

        #expect(store.preferences.speed(of: "sea-room-1", series: "Sea Room") == 1.4)
        #expect(store.preferences.speed(of: "sea-room-2", series: "Sea Room") == 0.9)
    }

    @Test("Another series is not offered it")
    func anotherSeriesIsNotOfferedIt() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(1.4, of: "sea-room-1", series: "Sea Room")

        #expect(store.preferences.speed(of: "another", series: "Somewhere Else") == 1)
    }

    /// A publication belonging to no series still remembers its own, and does not leak into
    /// every other publication that belongs to nothing.
    @Test("A publication with no series remembers its own")
    func noSeriesStillRemembers() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(2, of: "standalone", series: nil)

        #expect(store.preferences.speed(of: "standalone", series: nil) == 2)
        #expect(store.preferences.speed(of: "other", series: nil) == 1)
    }

    /// `settings-and-about` requires what the app remembers about reading to be clearable, and
    /// a speed is one of those things. Deliberately whole-store: a listener clearing their
    /// history does not mean "all but the series defaults".
    @Test("Clearing forgets everything, series defaults included")
    func clearingForgetsEverything() throws {
        let store = try fresh()
        defer { store.discard() }
        store.preferences.remember(1.4, of: "sea-room-1", series: "Sea Room")

        store.preferences.clear()

        #expect(store.preferences.speed(of: "sea-room-1", series: "Sea Room") == 1)
        #expect(store.preferences.speed(of: "sea-room-2", series: "Sea Room") == 1)
    }

    /// A store is not somewhere to validate a range, and it is not somewhere to invent one
    /// either: what comes back is what went in, and `PlaybackSpeed` is what clamps it. A
    /// preference file edited by hand, or written by an older build, must not be able to hand
    /// the player a rate it would refuse.
    @Test("A stored rate outside the offered range comes back as stored, for the player to clamp")
    func outOfRangeIsNotSilentlyRewritten() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(9, of: "wild", series: nil)

        #expect(store.preferences.speed(of: "wild", series: nil) == 9)
    }

    /// Nothing stored is not the same as a stored zero. `UserDefaults` answers `0` for a key it
    /// has never seen, so a store that trusted the number would start every untouched book
    /// stopped — which is the one value a speed may never be.
    @Test("A stored zero is not mistaken for a remembered speed")
    func zeroIsNotARememberedSpeed() throws {
        let store = try fresh()
        defer { store.discard() }

        store.preferences.remember(0, of: "sea-room-1", series: "Sea Room")

        #expect(store.preferences.speed(of: "sea-room-1", series: "Sea Room") == 1)
    }
}
