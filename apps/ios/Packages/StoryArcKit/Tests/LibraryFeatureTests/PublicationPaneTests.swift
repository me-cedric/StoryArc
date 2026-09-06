import Foundation
import Testing

/// The Library destination is a split, the page is registered in its detail column, and the
/// shelf column writes that column's path.
///
/// **What this guards is a mechanism, and for a day it guarded the wrong one.** The first
/// version pinned a single line's position — the page registered in the detail column and in
/// no earlier one — on the belief that a cover's value link in the leading column would then
/// land in the detail stack. It does not: SwiftUI's log says such a link *cannot be
/// activated*, and from 2026-09-05 13:05 to 2026-09-06 no cover on the shelf opened anything
/// on any device while this suite, `swift build`, `swiftlint --strict` and `xcodebuild build`
/// all stayed green. The registration's position still matters (a second one in the leading
/// column would push over the shelf); what makes a cover open at all is the shelf column
/// handing its cells `OpenPublicationRoute` and the detail stack being bound to `detailPath`,
/// and this file now pins both.
///
/// **So this reads source text, for the reason ``CoverRoutingWiringTests`` sets out at
/// length**: `swift test` runs on the host with no window, so the split cannot be composed
/// here and no assertion in this process can watch a pane draw. It is a tripwire, not a
/// proof. The proof is a phone walk opening a page from the shelf (`CurlWalkTests` does, on
/// its way to the reader) and the iPad frames `SweepIpadPanes` takes.
@Suite("The publication pane")
struct PublicationPaneTests {

    /// The composition, with its prose removed.
    ///
    /// `code(of:)` rather than `source(of:)`, and it is load-bearing here more than anywhere:
    /// the file argues at length about *which* column the registration belongs in and quotes
    /// both answers to do it. A guard reading the prose would pass on the documentation of
    /// the thing it is checking.
    private static let panes =
        LibraryFeatureSource.code(of: "Sources/LibraryFeature/LibraryPanes.swift")

    private static let view =
        LibraryFeatureSource.code(of: "Sources/LibraryFeature/LibraryView.swift")

    private static func lines(of code: String) -> [String] {
        code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Where the registration is written, one line at a time.
    private static let registration = ".publicationPages(in: model, onOpen: onOpen)"

    @Test("The Library destination is composed as a split")
    func theShelfIsASplit() {
        let code = Self.panes
        #expect(
            code.contains("NavigationSplitView(preferredCompactColumn: $compactColumn)"),
            """
            The shelf is no longer composed as a NavigationSplitView, so there is no second \
            pane and publication-detail's "the page appears beside the library" is unmet again.
            """
        )
        #expect(
            code.contains("if surface == .shelf {"),
            "The split is no longer gated to the Library destination."
        )
    }

    /// The one assertion this file exists for.
    @Test("The page is registered in the detail column and in no earlier one")
    func thePageBelongsToTheDetailColumn() throws {
        let all = Self.lines(of: Self.panes)
        let split = try #require(
            all.firstIndex { $0.hasPrefix("NavigationSplitView(") },
            "LibraryPanes.swift composes no NavigationSplitView."
        )
        let detail = try #require(
            all[split...].firstIndex { $0.hasPrefix("} detail: {") },
            "The split has no detail column."
        )
        let registrations = all.indices.filter { all[$0].hasPrefix(Self.registration) }

        #expect(
            registrations.count == 2,
            """
            Expected the publication page registered exactly twice — once in the split's \
            detail column, once in the plain stack the other surfaces use. Found \
            \(registrations.count) at lines \(registrations.map { $0 + 1 }).
            """
        )
        #expect(
            !registrations.contains(where: { $0 > split && $0 < detail }),
            """
            The leading column registers the publication page. A cover's link resolves \
            against the nearest container that declares its type, so it will push over the \
            shelf and the detail column will never show a page — which is the layout this \
            change replaced, drawn inside a split view that makes it look fixed.
            """
        )
        #expect(
            registrations.contains(where: { $0 > detail }),
            "The detail column does not register the publication page, so nothing can open in it."
        )
    }

    /// The mechanism the leading column actually has, since a value link there has none.
    @Test("The shelf column hands its covers the detail path, and the detail stack is bound to it")
    func theShelfWritesTheDetailPath() throws {
        let all = Self.lines(of: Self.panes)
        let split = try #require(
            all.firstIndex { $0.hasPrefix("NavigationSplitView(") },
            "LibraryPanes.swift composes no NavigationSplitView."
        )
        let detail = try #require(
            all[split...].firstIndex { $0.hasPrefix("} detail: {") },
            "The split has no detail column."
        )
        #expect(
            all[split..<detail].contains { $0.hasPrefix(".environment(\\.openPublicationRoute") },
            "The shelf column hands its covers no way to open a page, so a cover's tap does nothing."
        )
        #expect(
            all[detail...].contains { $0.hasPrefix("NavigationStack(path: $detailPath)") },
            "The detail stack is not bound to detailPath, so what the shelf writes is never shown."
        )
        for file in ["CoverCell.swift", "CoverList.swift"] {
            let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/\(file)")
            #expect(
                code.contains("@Environment(\\.openPublicationRoute)"),
                "A cover surface in the shelf column does not read the action the column hands it."
            )
        }
    }

    @Test("The detail column opens on the sentence, not on a publication")
    func theEmptyPaneSaysSo() throws {
        let all = Self.lines(of: Self.panes)
        let detail = try #require(
            all.firstIndex { $0.hasPrefix("} detail: {") },
            "The split has no detail column."
        )
        #expect(
            all[detail...].contains { $0.hasPrefix("PublicationDetailPlaceholder()") },
            """
            The detail column's root is not the empty-pane sentence. publication-detail asks \
            for "one sentence rather than showing an arbitrary publication or an empty \
            rectangle", and this is the pane it asks it of.
            """
        )
    }

    /// The shelf must not be able to answer the same question a second time.
    @Test("LibraryView registers no publication page of its own")
    func theViewDelegatesTheRegistration() {
        #expect(
            !Self.view.contains("publicationPages("),
            """
            LibraryView.swift registers the publication page again. Two registrations in two \
            containers is exactly the failure the split branch is written to avoid, and the \
            nearer one wins.
            """
        )
    }

    /// The sentence ships in every language the app does, and it is Android's own.
    ///
    /// Restored rather than written: the key, the four translations and the wording are the
    /// ones deleted on 2026-08-31, and `feature/library/.../strings.xml`'s
    /// `detail_pane_empty` still says them word for word. So no translator is owed anything
    /// by this change.
    @Test("The empty pane's sentence is translated everywhere the app ships")
    func theSentenceIsTranslated() {
        let localizations = LibraryFeatureSource.localizations(of: "detail.empty")
        for language in ["de", "en", "es", "fr"] {
            #expect(
                localizations[language] != nil,
                "detail.empty has no \(language) translation, and the app ships in \(language)."
            )
        }
    }
}
