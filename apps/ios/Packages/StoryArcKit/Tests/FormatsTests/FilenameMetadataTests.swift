import Foundation
import Testing

@testable import Formats

/// Driven entirely by the case table in the shared corpus manifest, so both
/// platforms agree on what "common naming pattern" means rather than each
/// inventing its own list. Android's `FilenameMetadataTest` reads the same table.
@Suite("Filename metadata")
struct FilenameMetadataTests {
    @Test("Every case in the shared table parses as recorded", arguments: FixtureCorpus.filenames)
    func matchesTheTable(expected: FixtureCorpus.FilenameCase) async throws {
        let parsed = FilenameMetadata(filename: expected.filename)
        #expect(parsed.series == expected.series, "\(expected.filename): \(expected.why)")
        #expect(parsed.number == expected.number, "\(expected.filename): \(expected.why)")
        #expect(parsed.volume == expected.volume, "\(expected.filename): \(expected.why)")
        #expect(parsed.year == expected.year, "\(expected.filename): \(expected.why)")
    }

    @Test("The table covers more than one naming convention")
    func tableIsNotTrivial() {
        // A guard on the corpus rather than on the parser: a table of one shape
        // would pass while proving nothing.
        #expect(FixtureCorpus.filenames.count >= 6)
    }

    @Test("Everything inferred says that it is inferred")
    func alwaysMarkedInferred() {
        // `publication-formats` requires it: an authoritative source has to be able
        // to replace a guess without raising a conflict the app invented.
        #expect(FilenameMetadata(filename: "Anything 001 (2020).cbz").isInferred)
    }

    @Test("A name with nothing to infer still yields a title")
    func bareName() {
        let parsed = FilenameMetadata(filename: "Watchmen.cbz")
        #expect(parsed.series == "Watchmen")
        #expect(parsed.number == nil)
    }

    @Test("An empty name infers nothing rather than an empty title")
    func emptyName() {
        #expect(FilenameMetadata(filename: "").series == nil)
        #expect(FilenameMetadata(filename: ".cbz").series == nil)
    }
}
