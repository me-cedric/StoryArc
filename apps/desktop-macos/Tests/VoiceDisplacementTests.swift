import Foundation
import Playback
import StoryArcCore
import Testing

@testable import StoryArc

/// Opening another book while a voice speaks ends the voice and says so once (`ebook-reader`, *Opening a different
/// publication*).
@MainActor
@Suite("Voice displacement")
struct VoiceDisplacementTests {
    private static func book(_ title: String, format: PublicationFormat) -> SpokenBook {
        let path = "/books/\(title).\(format.rawValue)"
        let publication = Publication(
            identity: .init(normalizedPath: path), format: format, displayTitle: title, origin: .inferred
        )
        return SpokenBook(publication: publication, url: URL(filePath: path))
    }

    @Test("Its own book keeps the voice; another ends it with one word naming the book; a narrator owes nothing")
    func displacedOnce() {
        let centre = PlayerCentre()
        let voice = Self.book("The Spoken Book", format: .epub)
        centre.begin(voice, source: FakeNarratedSource())

        let file = voice.url.path(percentEncoded: false)
        let own = ReaderTarget(publicationID: voice.publication.id, path: file, title: "Own")
        #expect(ReaderRoot.displaceVoice(opening: own, centre: centre) == .none)
        #expect(centre.book?.id == voice.publication.id, "reopening the book being spoken keeps its voice")
        let sameFile = ReaderTarget(publicationID: "placeholder", path: file, title: "Same file")
        #expect(ReaderRoot.displaceVoice(opening: sameFile, centre: centre) == .none)
        #expect(centre.book != nil, "a file the library does not list is still the book being spoken")

        let notice = ReaderRoot.displaceVoice(opening: Self.other("another"), centre: centre)
        #expect(notice.title == "The Spoken Book")
        #expect(centre.book == nil)
        #expect(ReaderRoot.displaceVoice(opening: Self.other("third"), centre: centre) == .none, "said once")

        centre.begin(Self.book("A Narrated Book", format: .m4b), source: FakeNarratedSource())
        #expect(ReaderRoot.displaceVoice(opening: Self.other("another"), centre: centre) == .none)
        #expect(centre.book == nil)
    }

    private static func other(_ name: String) -> ReaderTarget {
        ReaderTarget(publicationID: name, path: "/books/\(name).cbz", title: name)
    }
}
