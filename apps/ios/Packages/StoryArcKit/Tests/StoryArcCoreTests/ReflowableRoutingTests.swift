import Foundation
import Testing

@testable import StoryArcCore

/// Which of the two readers opens a publication.
///
/// `StoryArcApp` chooses between `EpubReaderView` and `ReaderView` on one condition, and
/// until this suite existed that condition had no name and no test — it was a clause in a
/// view body. It is not a spelling detail: it decides whether a reader gets typography
/// controls, and **the case it exists for is the one everybody gets wrong**.
///
/// A fixed-layout EPUB is an EPUB by format and a stack of pictures in fact. `ebook-reader`
/// puts it with the comic reader for that reason, and the comic reader has no theme control
/// at all. Two UI audits were fooled by this in one afternoon: each asked the shelf for "an
/// EPUB", each got a pre-paginated one — the corpus has two, `Bright Panels` and
/// `Glasshouse`, and they are the two whose titles sort first — and each then measured the
/// comic reader while reporting on the EPUB reader.
@Suite("Reflowable routing")
struct ReflowableRoutingTests {

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

    @Test("A reflowable EPUB opens the reflowable reader")
    func reflowableEpub() {
        #expect(publication(format: .epub).isReflowable)
    }

    @Test("A fixed-layout EPUB does not, however much of an EPUB it is")
    func fixedLayoutEpub() {
        // The whole point of the property. The format is `.epub` either way, so anything
        // that asks only the format routes this one to the wrong reader.
        let fixed = publication(format: .epub, isFixedLayout: true)

        #expect(fixed.format == .epub)
        #expect(fixed.isReflowable == false)
    }

    @Test("No other format is reflowable, PDF included")
    func everythingElse() {
        // PDF is the second thing that trips this: its pages are not images in a zip, so
        // `PublicationFormat.isPagedImages` says `false` — and it still opens the comic
        // reader, because it has pages at a fixed size. Format is not the question.
        for format in PublicationFormat.allCases where format != .epub {
            #expect(publication(format: format).isReflowable == false, "\(format)")
        }
    }
}
