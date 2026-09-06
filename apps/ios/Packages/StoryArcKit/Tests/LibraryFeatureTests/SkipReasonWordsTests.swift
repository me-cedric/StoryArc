import Foundation
import Formats
import Testing

@testable import LibraryFeature

/// Each refusal reaches the reader through a catalogue key, and through no other route.
///
/// The pair to `SkipReasonCatalogueTests`: that one asserts the eight keys are answerable in
/// four languages, this one asserts every case asks for one of them and that nothing in the
/// format layer can hand a view a sentence.
///
/// **The switch below is the guard, not the assertion.** It is exhaustive over `SkipReason`,
/// so a case added to the format layer stops this file compiling until somebody words it.
/// That is what makes *Reasons of different kinds in one list* enforceable: a new refusal
/// cannot reach the notice in English while its neighbours are in French.
@Suite("Every skipped-publication reason is worded by the library, not by the format layer")
struct SkipReasonWordsTests {

    /// Every refusal the scan can report.
    ///
    /// Written out because `SkipReason` carries a payload and cannot be `CaseIterable`. The
    /// exhaustive switch in ``key(of:)`` is what stops this list going stale.
    private static let everyReason: [SkipReason] = [
        .unsupportedFormat("CB7"),
        .notThere,
        .formatNotRecognised,
        .archivePasswordProtected,
        .archiveUnreadable,
        .pdfUnopenable,
        .contentProtected,
        .unknown,
    ]

    /// The key the library words this refusal with.
    ///
    /// Only `unsupportedFormat` binds anything, and what it binds is a format's name — which
    /// `localization`'s *A sentence built around content* keeps as content: the words around
    /// it are translated and the name is shown as it is. No other case carries a payload,
    /// which is the whole of "the format layer stops being able to hold a sentence".
    private func key(of reason: SkipReason) -> String {
        switch reason {
        case .unsupportedFormat: "library.skipped.reason.unsupported %@"
        case .notThere: "library.skipped.reason.notThere"
        case .formatNotRecognised: "library.skipped.reason.formatNotRecognised"
        case .archivePasswordProtected: "library.skipped.reason.archivePasswordProtected"
        case .archiveUnreadable: "library.skipped.reason.archiveUnreadable"
        case .pdfUnopenable: "library.skipped.reason.pdfUnopenable"
        case .contentProtected: "library.skipped.reason.contentProtected"
        case .unknown: "library.skipped.reason.unknown"
        }
    }

    @Test("The case set and the worded set are the same set")
    func everyCaseIsWorded() {
        #expect(
            Set(Self.everyReason.map(key(of:))) == Set(SkipReasonCatalogueTests.keys),
            "a refusal the scan can report has no key, or a key names no refusal"
        )
    }

    /// The mapping asks for exactly those keys, and asks for them as literals.
    ///
    /// `scripts/ios-strings.mjs` reads `Text("…")` out of the source, so a key reached through
    /// a variable is a key that gate cannot see — which is how thirty sentences shipped. The
    /// literals have to be here, in this file, one per case.
    @Test("The library's wording file asks for those keys and no others")
    func theWordingFileAsksForThem() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/SkipReasonWords.swift")

        for key in SkipReasonCatalogueTests.keys {
            // The catalogue key holds `%@`; the source holds the interpolation SwiftUI
            // derives it from, so the comparison is against everything before the hole.
            let asked = key.replacingOccurrences(of: " %@", with: " \\(")
            #expect(code.contains("\"\(asked)"), "SkipReasonWords.swift never asks for \(key)")
        }
        #expect(
            code.components(separatedBy: "Text(\"library.skipped.reason.").count - 1
                == SkipReasonCatalogueTests.keys.count,
            "SkipReasonWords.swift asks for a reason key that names no case"
        )
    }

    /// The drawing site draws the wording, rather than a string it was handed.
    ///
    /// Without this the mapping could be correct and unused, which is what the notice did for
    /// as long as the reason was a `String`: the format layer wrote the sentence and the view
    /// drew it verbatim.
    @Test("The notice and its list draw the worded reason")
    func theNoticeDrawsIt() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/SkippedNotice.swift")

        #expect(code.contains("reason.sentence"), "the banner does not draw the worded reason")
        #expect(
            code.contains("entry.reason.sentence"),
            "the list does not draw the worded reason"
        )
    }
}
