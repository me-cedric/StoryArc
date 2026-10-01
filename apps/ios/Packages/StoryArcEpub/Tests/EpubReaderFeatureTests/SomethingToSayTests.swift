import Foundation
import Testing
import ReadiumShared

@testable import EpubReaderFeature

/// `ebook-reader`, *A publication with nothing to say*: "the read-aloud control is absent
/// rather than present and refusing".
///
/// Readium gives every reflowable EPUB a content service, so the old answer — a service
/// exists — said yes to a book of bare images, and play then walked to the end in silence.
/// These hand ``EpubReaderModel/hasSomethingToSay(_:)`` the content an image-only book
/// yields, which no fixture in the corpus has.
@Suite("Whether a book has something to say")
struct SomethingToSayTests {

    @Test("A book of bare images has nothing to say")
    func bareImages() async {
        let content = Elements((0..<3).map { image(in: "page-\($0).xhtml") })
        #expect(await EpubReaderModel.hasSomethingToSay(content) == false)
    }

    @Test("One paragraph after the images is enough")
    func aParagraphAfterImages() async {
        let content = Elements([image(in: "page-0.xhtml"), paragraph("Call me Ishmael.", in: "page-1.xhtml")])
        #expect(await EpubReaderModel.hasSomethingToSay(content) == true)
    }

    @Test("A paragraph of white space says nothing")
    func whiteSpace() async {
        let content = Elements([paragraph(" \n\t", in: "page-0.xhtml")])
        #expect(await EpubReaderModel.hasSomethingToSay(content) == false)
    }

    @Test("A described image has something to say, because the synthesizer says the caption")
    func describedImage() async {
        let content = Elements([image(in: "page-0.xhtml", caption: "A lighthouse at dusk")])
        #expect(await EpubReaderModel.hasSomethingToSay(content) == true)
    }

    @Test("The walk gives up past its bound of resources")
    func bounded() async {
        let images = (0..<60).map { image(in: "page-\($0).xhtml") }
        let content = Elements(images + [paragraph("Too late to count.", in: "page-60.xhtml")])
        #expect(await EpubReaderModel.hasSomethingToSay(content) == false)
    }

    @Test("No content service at all has nothing to say")
    func noContent() async {
        #expect(await EpubReaderModel.hasSomethingToSay(nil) == false)
    }

    // MARK: - Content

    private func locator(_ href: String) -> Locator {
        Locator(href: URL(fileURLWithPath: "/book/\(href)"), mediaType: .xhtml)
    }

    private func image(in href: String, caption: String? = nil) -> any ContentElement {
        ImageContentElement(locator: locator(href), embeddedLink: Link(href: "image.png"), caption: caption)
    }

    private func paragraph(_ text: String, in href: String) -> any ContentElement {
        TextContentElement(
            locator: locator(href),
            role: .body,
            segments: [.init(locator: locator(href), text: text)]
        )
    }
}

/// A publication's content as a fixed list, in reading order.
private struct Elements: Content {
    let elements: [any ContentElement]

    init(_ elements: [any ContentElement]) { self.elements = elements }

    func iterator() -> any ContentIterator { Walk(elements) }

    private final class Walk: ContentIterator {
        private let elements: [any ContentElement]
        private var index = -1

        init(_ elements: [any ContentElement]) { self.elements = elements }

        func next() async throws -> (any ContentElement)? {
            guard index + 1 < elements.count else { return nil }
            index += 1
            return elements[index]
        }

        func previous() async throws -> (any ContentElement)? {
            guard index > 0 else { return nil }
            index -= 1
            return elements[index]
        }
    }
}
