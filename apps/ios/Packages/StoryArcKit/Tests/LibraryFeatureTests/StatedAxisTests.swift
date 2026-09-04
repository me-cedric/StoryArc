import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The two axes a reader narrows by, and the controls that are supposed to state them.
///
/// `library-browsing` keeps **availability** — everything, or only what opens with no network
/// — apart from **source**, the library a publication came from. They are different questions,
/// they are cleared by different actions, and the spec is careful about which is which. Three
/// findings in the 2026-09-02 sweep are one mistake: a control that states the wrong axis, or
/// does not state one at all.
///
/// **These read source text and the string catalogue**, the trade `LibraryToolbarTests` and
/// `GlassIsUntintedTests` make and explain: composing a toolbar or a `List` needs a window and
/// `swift test` runs on the host. What regressed here is not a rendered pixel but which words
/// and which glyph a control was given, and both are things text can check exactly. The
/// pictures are the other half and are not optional —
/// `docs/designs/screenshots/stated-axes-2026-09-04/` holds them.
@Suite("The controls state the axis they narrow by")
struct StatedAxisTests {

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

    /// A file's code, with `//` prose removed.
    ///
    /// Every one of these files argues its own case at length and several quote the very
    /// symbol names being asserted on. A guard that counted those words would be measuring
    /// the documentation of the change rather than the change.
    private static func code(of relativePath: String) -> String {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// One key's value in every language the app ships.
    private static func strings(_ key: String) throws -> [String: String] {
        let path = "Sources/LibraryFeature/Resources/Localizable.xcstrings"
        let data = try #require(source(path).data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let all = json?["strings"] as? [String: Any]
        let entry = try #require(all?[key] as? [String: Any], "\(key) is not in the catalogue.")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        return localizations.compactMapValues { value in
            let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any]
            return unit?["value"] as? String
        }
    }

    // MARK: - Narrowing to one library is not a statement about the device

    /// Filter → *Which library* → `Attic NAS` emptied the shelf and answered *"Nothing from
    /// Attic NAS is on this device yet."* The reader narrowed by **source** and was told about
    /// **availability** — the one distinction this capability is most careful to keep.
    @Test("The one-library empty state names the library, never the device")
    func scopeEmptyStateNamesTheLibrary() throws {
        let scoped = try Self.strings("library.empty.scope %@")
        #expect(scoped.count == 4, "Every language the app ships has to answer this.")
        for (language, sentence) in scoped {
            #expect(
                sentence.contains("%@"),
                "\(language) dropped the library's name from the sentence naming it."
            )
        }
        let english = try #require(scoped["en"])
        #expect(!english.lowercased().contains("on this device"))
        #expect(english.lowercased().contains("library"))
    }

    /// The device axis keeps its own sentence, and it is the one that may say *on this device*.
    /// Asserted beside the above so a future edit cannot fix one by breaking the other.
    @Test("The on-this-device empty state still names the device")
    func availabilityEmptyStateNamesTheDevice() throws {
        let english = try #require(try Self.strings("library.empty.onDevice")["en"])
        #expect(english.lowercased().contains("on this device"))
    }

    // MARK: - The search screen states its scope

    /// `library-browsing`: "**WHEN** the search screen is open **THEN** it states whether it is
    /// searching everything or only what is on the device". The results *are* the search
    /// screen, and the statement was on the at-rest screen alone.
    @Test("Both faces of the search screen state the scope, through one control")
    func bothSearchSurfacesStateTheirScope() {
        let results = Self.code(of: "Sources/LibraryFeature/SearchResultsView.swift")
        let atRest = Self.code(of: "Sources/LibraryFeature/SearchAtRest.swift")
        #expect(results.contains("SearchScopeStatement("))
        #expect(atRest.contains("SearchScopeStatement("))
    }

    /// One type, so the two cannot drift into two different controls for one idea.
    @Test("The scope statement is defined once")
    func theScopeStatementIsOneType() {
        let statement = Self.code(of: "Sources/LibraryFeature/SearchScopeStatement.swift")
        #expect(statement.contains("struct SearchScopeStatement"))
        #expect(statement.contains(".pickerStyle(.segmented)"))
    }

    // MARK: - A search that mostly failed says so once

    /// Three servers, none running — which is every train journey — produced three *didn't
    /// answer* lines with three *Try again* buttons under two results.
    @Test("Every library that went quiet is named in one sentence")
    func silentLibrariesAreNamedTogether() {
        let sources = [
            SearchListing.SilentSource(sourceID: "a", name: "Attic NAS"),
            SearchListing.SilentSource(sourceID: "b", name: "StoryArc Test Catalogue"),
            SearchListing.SilentSource(sourceID: "c", name: "ada · 127.0.0.1")
        ]
        let phrase = SearchResultsView.named(sources)
        for source in sources {
            #expect(phrase.contains(source.name), "\(source.name) is not in the notice.")
        }
        // One phrase, not three lines: a separator between the first two and a conjunction
        // before the last is what a list formatter produces and what a sentence needs.
        #expect(phrase.contains(","))
    }

    /// One library is still one name, with no stray punctuation around it.
    @Test("One quiet library reads as a name, not a list")
    func oneSilentLibraryReadsPlainly() {
        let one = [SearchListing.SilentSource(sourceID: "a", name: "Attic NAS")]
        #expect(SearchResultsView.named(one) == "Attic NAS")
    }

    /// The row that was a `ForEach` is one row now.
    @Test("The results screen draws one notice, not one per library")
    func theResultsScreenDrawsOneNotice() {
        let results = Self.code(of: "Sources/LibraryFeature/SearchResultsView.swift")
        #expect(!results.contains("ForEach(listing.silent)"))
        #expect(results.contains("silentNotice(listing.silent)"))
    }

    // MARK: - The View menu says what it decides

    /// The menu deciding availability, layout, sort and direction was drawn as an ellipsis
    /// whenever the shelf showed everything — so the requirement that the availability choice
    /// be "visible while it is active" was met in one of its two states, and the glyph a reader
    /// learned meant *downloaded* rather than *availability*.
    @Test("The View menu draws the availability axis, not an ellipsis")
    func theViewMenuStatesItsAxis() {
        let controls = Self.code(of: "Sources/LibraryFeature/LibraryBrowsingControls.swift")
        #expect(!controls.contains("ellipsis.circle"))
        #expect(controls.contains("Image(systemName: availability.symbolName)"))
    }

    /// Both values are drawable, which is what makes the label a statement in either state.
    @Test("Each availability choice has a symbol of its own")
    func eachAvailabilityHasItsOwnSymbol() {
        let symbols = Set(LibraryAvailability.allCases.map(\.symbolName))
        #expect(symbols.count == LibraryAvailability.allCases.count)
        #expect(!symbols.contains("ellipsis.circle"))
    }

    /// `library-browsing` asks for the active count to be visible on the control. It was
    /// spoken to VoiceOver and never drawn, so one filter looked exactly like six.
    @Test("The filter count is drawn as well as spoken")
    func theFilterCountIsDrawn() {
        let menu = Self.code(of: "Sources/LibraryFeature/LibraryFilterMenu.swift")
        #expect(menu.contains("Text(narrowing.activeCount, format: .number)"))
        // Still spoken: drawing it is an addition, not a replacement, and a reader using
        // VoiceOver gets the sentence rather than the digit.
        #expect(menu.contains("library.filter.active \\(narrowing.activeCount)"))
    }

    // MARK: - The action on a form is not a fifth field

    /// *Connect* was a full-width grey capsule the same colour, height and corner as the
    /// fields above it — because `.borderedProminent` renders grey while disabled, and the
    /// share sheet's was an unstyled `Form` row, which renders as a field-shaped capsule.
    @Test("Each add-a-library form emphasises its action the way this app emphasises")
    func theConnectButtonsAreProminent() {
        for sheet in ["SmbSheet", "CatalogueSheet", "KavitaSheet"] {
            let code = Self.code(of: "Sources/LibraryFeature/\(sheet).swift")
            #expect(
                code.contains(".buttonStyle(.glassProminent)"),
                "\(sheet)'s action is not emphasised the way design.md emphasises."
            )
            // `.tint` on plain `.glass` tints the material and flattens it —
            // `GlassIsUntintedTests` fails the build over exactly that, and this is the
            // variant meant to carry a tint.
            #expect(!code.contains(".buttonStyle(.glass)\n"))
        }
    }
}
