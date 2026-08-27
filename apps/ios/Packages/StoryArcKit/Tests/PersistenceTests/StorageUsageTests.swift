import Foundation
import Testing

@testable import Persistence

/// What a size looks like to a reader, and in whose number format.
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

    @Test("Small sizes stay whole, because a fraction of a kilobyte tells nobody anything")
    func smallSizesAreWhole() {
        #expect(formattedBytes(0) == "0 kB")
        #expect(formattedBytes(400) == "1 kB")
        #expect(formattedBytes(4096) == "4 kB")
    }
}
