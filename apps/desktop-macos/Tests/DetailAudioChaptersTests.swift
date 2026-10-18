import Foundation
import Playback
import StoryArcCore
import Testing

@testable import StoryArc

/// An audiobook's page (`audio-playback`, *The chapter list on the publication's page*, *The primary action says
/// where it will resume*, *An audiobook with one part*).
@MainActor
@Suite("Audiobook page")
struct DetailAudioChaptersTests {
    private static let identity = PublicationIdentity(normalizedPath: "/books/chaptered.m4b")

    private static func listening(part: Int, finished: Bool = false) -> ReadingProgress {
        ReadingProgress(
            identity: identity, position: .listening(part: part, partCount: 3, offset: 1, of: 2),
            isFinished: finished, updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("The fixture's three chapters are read from the file")
    func readsTheChapters() async {
        let parts = await DetailAudioChapters.parts(of: TestFixtures.audiobooks.appending(path: "chaptered.m4b"))
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.duration != nil })
    }

    @Test("Never started says listen; part way says the chapter by name; a finished book says listen again")
    func primaryWords() {
        let parts = [
            AudiobookPart(url: URL(filePath: "/b.m4b"), title: "One", start: 0, duration: 2),
            AudiobookPart(url: URL(filePath: "/b.m4b"), title: "Two", start: 2, duration: 2),
        ]
        #expect(DetailAudioChapters.primary(nil, parts: parts) == .listen)
        #expect(DetailAudioChapters.primary(Self.listening(part: 1), parts: parts) == .resume("Two"))
        #expect(DetailAudioChapters.primary(Self.listening(part: 1, finished: true), parts: parts) == .listen)
        #expect(DetailAudioChapters.primary(Self.listening(part: 0), parts: [parts[0]]) == .continueListening)
    }
}
