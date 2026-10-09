import Foundation
import Testing

@testable import StoryArcCore

/// `reading-progress`, *Resume at the first visible element*, decision O27. Android's
/// `ElementLocatorTest` asserts the same rows.
@Suite("A reflowable position also holds its first visible element")
struct ElementLocatorTests {

    static let element = ElementLocator(
        href: "OEBPS/ch1.xhtml",
        cssSelector: "body > p:nth-child(18)",
        textBefore: "the end of seventeen. ",
        textAfter: "Paragraph eighteen begins",
        publicationDigest: "d2"
    )

    @Test("The same file and the same resource resume at the element")
    func theSameResourceResumesAtTheElement() {
        #expect(Self.element.resumes(publicationDigest: "d2", resource: "OEBPS/ch1.xhtml"))
        #expect(Self.element.resumes(publicationDigest: "d2", resource: "OEBPS/ch1.xhtml#p18"))
    }

    @Test("Another resource or another file falls back to the fraction")
    func anotherResourceFallsBack() {
        #expect(!Self.element.resumes(publicationDigest: "d2", resource: "OEBPS/ch2.xhtml"))
        #expect(!Self.element.resumes(publicationDigest: "d9", resource: "OEBPS/ch1.xhtml"))
        #expect(!Self.element.resumes(publicationDigest: nil, resource: "OEBPS/ch1.xhtml"))
    }

    @Test("Nothing is captured without a digest, a selector or visible text")
    func nothingToAnchorOnIsNotCaptured() {
        func captured(selector: String? = "p", after: String? = "Text", digest: String? = "d2") -> ElementLocator? {
            ElementLocator.captured(
                href: "ch1", cssSelector: selector, textBefore: nil, textAfter: after, publicationDigest: digest
            )
        }
        #expect(captured() != nil)
        #expect(captured(digest: nil) == nil)
        #expect(captured(selector: "") == nil)
        #expect(captured(after: " \n ") == nil)
    }

    @Test("Each side keeps at most the limit, nearest the point")
    func eachSideIsCapped() throws {
        let long = String(repeating: "a", count: 100) + "B"
        let element = try #require(
            ElementLocator.captured(
                href: "ch1", cssSelector: "p", textBefore: long, textAfter: "C" + long, publicationDigest: "d2"
            )
        )
        #expect(element.textBefore?.count == ElementLocator.textLimit)
        #expect(element.textBefore?.hasSuffix("B") == true)
        #expect(element.textAfter.count == ElementLocator.textLimit)
        #expect(element.textAfter.hasPrefix("C"))
    }

    @Test("A stored position written before the element existed still reads")
    func anOlderStoredPositionStillReads() throws {
        let older = Data(#"{"reflowable":{"progression":0.45,"locator":""}}"#.utf8)

        let position = try JSONDecoder().decode(ReadingPosition.self, from: older)

        #expect(position == .reflowable(progression: 0.45, locator: ""))
    }

    @Test("A stored position keeps its element")
    func theStoredPositionKeepsItsElement() throws {
        let position = ReadingPosition.reflowable(progression: 0.45, locator: "{}", firstVisibleElement: Self.element)

        let read = try JSONDecoder().decode(ReadingPosition.self, from: JSONEncoder().encode(position))

        #expect(read == position)
    }

    @Test("A document position without the element reads, and the element round-trips")
    func theDocumentCarriesTheElement() throws {
        let older = Data(#"{"kind":"reflowable","progression":0.45,"locator":""}"#.utf8)
        #expect(
            try JSONDecoder().decode(DocumentPosition.self, from: older).position
                == .reflowable(progression: 0.45, locator: "")
        )

        let position = ReadingPosition.reflowable(progression: 0.45, locator: "", firstVisibleElement: Self.element)
        let written = try JSONEncoder().encode(DocumentPosition(position))
        #expect(try JSONDecoder().decode(DocumentPosition.self, from: written).position == position)
    }

    @Test("An element this build cannot read is dropped and the fraction stays")
    func anUnreadableElementLeavesTheFraction() throws {
        let newer = Data(
            #"{"kind":"reflowable","progression":0.45,"locator":"","firstVisibleElement":{"href":"ch1"}}"#.utf8
        )

        #expect(
            try JSONDecoder().decode(DocumentPosition.self, from: newer).position
                == .reflowable(progression: 0.45, locator: "")
        )
    }

    @Test("A field inside the element that this build does not know is ignored")
    func aNewerFieldInTheElementIsIgnored() throws {
        let newer = Data(
            #"""
            {"kind":"reflowable","progression":0.45,"locator":"","firstVisibleElement":{"href":"OEBPS/ch1.xhtml",
            "cssSelector":"body > p:nth-child(18)","textBefore":"the end of seventeen. ",
            "textAfter":"Paragraph eighteen begins","publicationDigest":"d2","fontScale":1.15}}
            """#.utf8
        )

        let position = try JSONDecoder().decode(DocumentPosition.self, from: newer).position

        #expect(position == .reflowable(progression: 0.45, locator: "", firstVisibleElement: Self.element))
    }
}
