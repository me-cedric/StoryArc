import Foundation
import Testing

/// That a browsed row lifts into its own card, and never into an empty one.
///
/// `.contextMenu(menuItems:preview:)` draws its preview container around whatever the preview
/// builder returns, so a builder that produces no view replaces the pressed row with an empty
/// card. `HeldSearchResultRow` has picked between the two overloads for that reason since it
/// was written; `KavitaChapterList` and `CatalogueEntryLink` draw rows whose publication
/// exists only once this device has indexed it, so they have to pick too.
///
/// **These read the two views as source text.** A SwiftUI body is not somewhere this can be
/// asserted — `KnownKavitaChapterTests` and `KnownCatalogueEntryTests` already pin the rule
/// the branch asks, and the branch itself is reachable only by rendering — so the choice is
/// this guard or no guard, which is the trade `KeepForOfflineWiringTests` makes and explains.
/// Comment lines are stripped first, so an explanation of the old defect does not read as the
/// defect.
@Suite("A browsed row lifts into its own card")
struct BrowsedRowLiftTests {
    /// One `LibraryFeature` source file with its comment lines left out.
    private static func source(_ name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/LibraryFeatureTests/this file
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
        let text = try #require(try? String(contentsOfFile: path, encoding: .utf8), "\(path) could not be read")
        return text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func count(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    @Test("Each browsed row attaches its menu twice, and the preview to only one of the two", arguments: [
        "KavitaChapterList.swift",
        "CatalogueGroups.swift",
    ])
    func thePreviewIsAttachedOnlyToTheResolvedBranch(file: String) throws {
        let source = try Self.source(file)
        #expect(
            Self.count(of: "contextMenu", in: source) == 2,
            "\(file) attaches its menu once, so one kind of row is drawn with the other's preview."
        )
        #expect(
            Self.count(of: "preview:", in: source) == 1,
            "\(file) offers a preview to a row that may have no card to show."
        )
    }

    @Test("A browsed Kavita chapter asks whether it is indexed before it offers a card")
    func theChapterRowAsksWhetherItIsIndexed() throws {
        let source = try Self.source("KavitaChapterList.swift")
        #expect(source.contains("knownKavitaChapter("))
    }

    @Test("A catalogue entry this device has not indexed still offers Open")
    func theCatalogueMenuOffersOpen() throws {
        // `library-browsing`'s *A publication's actions wherever it is drawn*. An indexed
        // entry gets `PublicationActionMenu`, which carries Open itself; the two branches
        // beside it had no row for the one thing the tap already does, so the long press
        // offered a shorter list than Android's `CatalogueEntryCell`, which draws it first.
        let source = try Self.source("CatalogueGroups.swift")
        #expect(source.contains("library.action.open"))
    }
}
