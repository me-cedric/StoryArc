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
/// were being shown. The owner's answer for `one-vocabulary-in-four-languages` task 4.3 is
/// that the destination is named by its location — "on this device", the same words on both
/// platforms — and that what the figure counts is stated where a reader has room to read it,
/// on the screen this row opens. `OfflineDestinationNameTests` guards the words themselves;
/// what is asserted here is the branch and the figure.
/// **`@MainActor` because every comparison below reads the size helper twice**, and the
/// helper follows the interface language. `ChosenLanguageFormattingTests` moves that choice
/// on the main actor and puts it back before its case returns, so a main-actor case here
/// reads one language on both sides of an `==`.
@MainActor
@Suite("Storage summaries")
struct StorageSummaryTests {

    /// Which of the two the row takes, not what it then says — the words are checked
    /// by `OfflineDestinationNameTests`, in four languages and against Android's.
    @Test("An empty download store takes the branch that states nothing, not a figure")
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
