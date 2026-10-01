import Foundation
import Testing

@testable import Persistence

/// What a size looks like to a reader, and in whose number format.
///
/// **`@MainActor` because these sizes follow the interface language**, which is one value for
/// the whole process. `ChosenLanguageFormattingTests` moves that value, and its cases are
/// main-actor and synchronous, as these are: a case here cannot start inside the window
/// another case holds French open. Without the annotation this suite runs on another thread
/// and reads "1,4 MB" while asking for the host's own decimal point.
@MainActor
@Suite("Storage usage")
struct StorageUsageTests {
    @Test("A size follows the reader's own number format")
    func sizeFollowsTheLocale() {
        // `String(format: "%.1f")` composes a fixed decimal point, so a French reader saw
        // "1.4 MB" where every other app on their phone says "1,4". `localization`
        // requires file sizes to follow the locale.
        let megabyte = Int64(1.4 * 1024 * 1024)
        let formatted = formattedBytes(megabyte)

        #expect(formatted.hasSuffix(" MB"))
        // The separator the current locale actually uses, whatever the test host is set
        // to — asserting a comma would only pass in France.
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(formatted.contains(separator), "\(formatted) has no \(separator)")
    }

    @Test("A size is the platform's own formatter, not a hand-written kB/MB/GB switch")
    func sizeIsThePlatformFormatter() {
        // `formattedBytes` used to hand-compose "kB"/"MB"/"GB" with a fixed decimal point.
        // Task 15.3 replaces it with `DownloadStore.formatted`, the one place that formatter
        // is already asked for `.storyArc`. Asserting equality with that call, rather than a
        // literal, is what catches the switch coming back.
        #expect(formattedBytes(0) == DownloadStore.formatted(0))
        #expect(formattedBytes(400) == DownloadStore.formatted(400))
        #expect(formattedBytes(4096) == DownloadStore.formatted(4096))
    }
}
