import Foundation
import Testing
import UniformTypeIdentifiers

@testable import LibraryFeature

/// One screen may put up one document picker, and the library used to declare two.
///
/// **This is the sweep's worst finding, and it was not the row's fault.** *Add a folder* was
/// reported as opening nothing while *Open a file*, one row below it in the same menu, put up
/// the system browser within three seconds — so the row, the button and the menu were all
/// suspected in turn. They were all fine. ``LibraryView`` applied two `.fileImporter`
/// modifiers to one view, and SwiftUI honours the **last** one applied: the folder importer
/// was declared first and was shadowed by the import picker declared under it. The reader saw
/// a menu row that did nothing, and on iOS the folder picker is the whole of adding a local
/// library, so that row was the only way in.
///
/// **Proved on the simulator by swapping the two, and nothing else.** With the order reversed,
/// `SweepSourcesTests.testCaptureFolderPicker` passed and produced the first
/// `ios-add-folder-picker.png` this repository has ever held, and
/// `testCaptureFilePicker` — which had passed on every previous run — failed with the same
/// sentence the folder walk used to fail with: *nothing came up over the shelf in ten
/// seconds*. One variable moved and the defect moved with it. See
/// `docs/designs/screenshots/one-picker-2026-09-04/README.md`.
///
/// So the fix is not an order. An order is a thing a later edit re-shuffles without knowing
/// it is load-bearing, and the failure it causes is invisible to every gate this project
/// runs. There is one picker now, and ``LocalPick`` decides what it offers — which makes two
/// simultaneous pickers unrepresentable rather than merely currently-absent.
///
/// **This reads source text**, the trade `LibraryToolbarTests` and `GlassIsUntintedTests`
/// make and explain: presenting a `fileImporter` needs a window, `swift test` runs on the
/// host, and what regressed here is not a rendered pixel but the number of presentations
/// declared on one view. Text can count that exactly, and nothing else in `pnpm check` can
/// count it at all.
@Suite("The library puts up one document picker, not two")
struct LocalPickerTests {

    /// A source file in the package under test, reached from this file rather than discovered.
    ///
    /// `#filePath` rather than a walk looking for a marker directory: this repository nests
    /// agent worktrees at `.claude/worktrees/<name>/`, and a walk that climbs out of the
    /// checkout under test guards the parent repository's copy instead. That has happened.
    private static func source(_ relativePath: String) -> String {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: relativePath)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("\(relativePath) is not at \(file.path) — has it moved?")
        }
        return text
    }

    /// A file's lines, with `//` prose removed and each line trimmed.
    ///
    /// The prose below explains the defect at length and names every modifier involved. A
    /// guard that counted those words would be measuring the documentation of the fix rather
    /// than the fix.
    private static func code(of relativePath: String) -> [String] {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Every modifier in this module that ends in a document picker being presented.
    ///
    /// Named rather than inferred. `pickingLocalLibrary` presents one; a bare `.fileImporter`
    /// is one; and a helper that wraps one — `importingPublications` was such a helper, and
    /// it is exactly what made the second presentation hard to see at the call site, because
    /// its name says nothing about a picker.
    private static let presenters = [".fileImporter(", ".pickingLocalLibrary(", ".importingPublications("]

    private static func presentations(in relativePath: String) -> Int {
        code(of: relativePath).count { line in
            presenters.contains { line.hasPrefix($0) }
        }
    }

    @Test("The shelf declares one picker presentation, not two")
    func shelfDeclaresOnePicker() {
        let found = Self.presentations(in: "Sources/LibraryFeature/LibraryView.swift")
        #expect(
            found == 1,
            """
            LibraryView applies \(found) document-picker presentations to one view. SwiftUI \
            honours the last one applied and silently drops the rest, which is how *Add a \
            folder* came to open nothing while *Open a file* worked. One presentation, and \
            LocalPick chooses what it offers.
            """
        )
    }

    /// The other screen that offers both, and it had the same defect the other way round.
    ///
    /// Home stacked the two in the opposite order to the shelf — the import first, the folder
    /// under it — so on Home the folder picker was the one that worked and *Open a comic* was
    /// the row that did nothing. Nobody had reported it, because Home only offers either when
    /// the library is empty, and the sweep photographed a device with fourteen publications on
    /// it. It was found by the compiler while the shelf was being fixed: a second call site of
    /// a modifier that no longer existed. **That is the argument for the count rather than the
    /// order** — the same mistake was already in the codebase twice, in two arrangements, and
    /// no gate could see either.
    @Test("Home declares one picker presentation")
    func homeDeclaresOnePicker() {
        let found = Self.presentations(in: "Sources/LibraryFeature/HomeScreen.swift")
        #expect(found == 1, "HomeScreen applies \(found) document-picker presentations, not 1.")
    }

    /// The guard can only guard what it can find.
    @Test("The guard is reading a file that still exists")
    func theGuardFindsItsSubject() {
        #expect(Self.code(of: "Sources/LibraryFeature/LibraryView.swift").count > 100)
        #expect(Self.presenters.allSatisfy { $0.hasPrefix(".") })
    }

    // MARK: - What each pick offers

    @Test("Picking a folder offers folders and nothing else")
    func folderOffersFolders() {
        #expect(LocalPick.folder.contentTypes == [.folder])
    }

    /// The import picker still offers what `local-library` says it may offer.
    ///
    /// Unfolded from ``ImportableTypes`` rather than restated, so a format added there
    /// reaches the picker without this test having to be told.
    @Test("Picking a file offers the importable types")
    func fileOffersImportableTypes() {
        #expect(LocalPick.file.contentTypes == ImportableTypes.all)
        #expect(!LocalPick.file.contentTypes.contains(.folder))
    }

    /// CB7 stays out, and a folder never becomes an importable type by accident.
    @Test("The two picks never offer the same thing")
    func thePicksAreDistinct() {
        let shared = Set(LocalPick.folder.contentTypes).intersection(LocalPick.file.contentTypes)
        #expect(shared.isEmpty)
    }
}
