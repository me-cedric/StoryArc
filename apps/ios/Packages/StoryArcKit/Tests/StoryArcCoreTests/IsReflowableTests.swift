import Foundation
import Testing

@testable import StoryArcCore

/// ``Publication/isReflowable`` — the rule the app routes on, as a property.
///
/// **This suite asserts the property and nothing else.** It used to be called "Reflowable
/// routing" and its documentation said "which of the two readers opens a publication", which
/// was a promise it could not keep: inverting the condition in `StoryArcApp`'s view body left
/// every test here passing. The routing site has its own guard, ``ReaderRoutingWiringTests``,
/// and that one fails on the inversion.
///
/// The property is still worth naming and testing. It decides whether a reader gets
/// typography controls, and **the case it exists for is the one everybody gets wrong**: a
/// fixed-layout EPUB is an EPUB by format and a stack of pictures in fact, so `ebook-reader`
/// renders it with the paginated behaviour of `comic-reader` and hides the typography
/// controls rather than showing them disabled.
///
/// Two UI audits asked the shelf for "an EPUB" and neither recorded which of the two readers
/// it reached — a cover's spoken label carries the format and says nothing about the layout,
/// so a pre-paginated one satisfies the filter. Under the shelf's default title sort the two
/// pre-paginated fixtures in `scripts/corpus.mjs`, `Bright Panels` and `Glasshouse`, sort
/// before the three reflowable ones, which is enough to explain what those runs reported
/// without a defect in the reflowable reader. It is not proof of what they opened: the
/// shelf's sort is persisted per reader and the UI tests reset no app state.
@Suite("Publication.isReflowable")
struct IsReflowableTests {

    private func publication(
        format: PublicationFormat,
        isFixedLayout: Bool = false
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/one"),
            format: format,
            displayTitle: "One",
            origin: .inferred,
            isFixedLayout: isFixedLayout
        )
    }

    @Test("A reflowable EPUB is reflowable")
    func reflowableEpub() {
        #expect(publication(format: .epub).isReflowable)
    }

    @Test("A fixed-layout EPUB is not, however much of an EPUB it is")
    func fixedLayoutEpub() {
        // The whole point of the property. The format is `.epub` either way, so anything
        // that asks only the format gets this one wrong.
        let fixed = publication(format: .epub, isFixedLayout: true)

        #expect(fixed.format == .epub)
        #expect(fixed.isReflowable == false)
    }

    @Test("No other format is reflowable, PDF included")
    func everythingElse() {
        // PDF is the second thing that trips this: its pages are not images in a zip, so
        // `PublicationFormat.isPagedImages` says `false` — and it is still not reflowable,
        // because it has pages at a fixed size. Format is not the question.
        for format in PublicationFormat.allCases where format != .epub {
            #expect(publication(format: format).isReflowable == false, "\(format)")
        }
    }
}
