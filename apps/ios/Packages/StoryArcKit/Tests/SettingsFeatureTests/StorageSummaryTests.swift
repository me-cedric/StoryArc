import Persistence
import StoryArcCore
import SwiftUI
import Testing

@testable import SettingsFeature

/// What Settings says about storage, and what it is saying it *about*.
///
/// The September sweep found four screens disagreeing. Settings' root said "Downloads and
/// storage — Nothing on this device", its own screen said "Space used — Zero kB", and the
/// Privacy screen said "Downloads · 0 bytes" with *Clear* greyed out, while the Downloads
/// destination showed nine publications under "On this device".
/// (`ios-settings-root.png`, `ios-settings-downloads.png`, `ios-settings-privacy.png`
/// against `ios-downloads-shelf.png`.)
///
/// **Both readings were right, which is why neither number changed.** This figure is what
/// StoryArc's own files weigh — `DownloadStore.bytesOnDisk()`, walked off the disk. The
/// destination's shelf is everything readable with no network, which `offline-downloads`
/// says explicitly holds publications "whatever source [they] came from and however [they]
/// got there" — a folder the reader picked included, and those bytes are not the app's to
/// count or to free. What was missing was any way for a reader to see which of the two they
/// were being shown. So every one of these lines names downloads now, and none of them
/// claims to describe the device.
@Suite("Storage summaries")
struct StorageSummaryTests {

    /// The root row's own words. It said *Nothing on this device* over a device with nine
    /// publications on it; what is true is that nothing has been downloaded.
    @Test("An empty download store is stated as no downloads, not as an empty device")
    func none() {
        let key = SettingsGroup.downloads.summaryKey(for: AppSettings(), LibrarySummary())
        #expect(key == LocalizedStringKey("settings.downloads.none"))
    }

    /// And with something in it, the row states the figure instead.
    ///
    /// The branch, not the interpolation: `LocalizedStringKey`'s `==` compares its format
    /// arguments, and two `FormatArgument`s built from the same string are not equal to each
    /// other — so an assertion written the obvious way fails on a key it has just built. The
    /// figure itself is asserted below, where it is a `String` and can be.
    @Test("A download store with files in it states what they weigh")
    func some() {
        let summary = LibrarySummary(sources: 1, bytesOnDisk: 129_000)
        let key = SettingsGroup.downloads.summaryKey(for: AppSettings(), summary)
        #expect(key != LocalizedStringKey("settings.downloads.none"))
        #expect(summary.formattedBytes == DownloadStore.formatted(129_000))
    }

    /// **One number, written one way.** `Zero kB` on one screen and `0 bytes` on the next
    /// are the same figure looking like two, and the platform formatter spells zero out
    /// unless it is told not to. `PrivacySettings` had already turned that off for its own
    /// row and said in a comment that the other two showed the figure "this way"; they did
    /// not. Now they do.
    @Test("Nothing is written as a number, the same way everywhere")
    func zeroIsANumber() {
        #expect(LibrarySummary(bytesOnDisk: 0).formattedBytes == DownloadStore.formatted(0))
        #expect(!LibrarySummary(bytesOnDisk: 0).formattedBytes.lowercased().contains("zero"))
    }

    /// The same helper the three screens call, asserted against the same figure rather than
    /// against a literal — a test that hard-coded "0 bytes" would be asserting the
    /// platform's spelling in one locale.
    @Test("Every screen formats the figure through one helper")
    func oneHelper() {
        #expect(LibrarySummary(bytesOnDisk: 129_000).formattedBytes == DownloadStore.formatted(129_000))
    }
}
