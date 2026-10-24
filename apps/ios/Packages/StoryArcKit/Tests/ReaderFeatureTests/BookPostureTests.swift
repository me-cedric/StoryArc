import Foundation
import Testing

import StoryArcCore
@testable import ReaderFeature

/// `foldables-and-iphone-duo` D4 and 2.4: held like a book, the reader offers no Curl, because a
/// curl across a half-open fold draws a crease the shader cannot model.
@MainActor
@Suite("A book posture withholds Curl")
struct BookPostureTests {
    private let url = URL(fileURLWithPath: "/fixtures/book-posture.cbz")

    private func model() -> ReaderModel {
        ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .cbz,
                displayTitle: "book-posture.cbz",
                origin: .inferred
            ),
            url: url
        )
    }

    @Test("The transition picker offers no Curl in a book posture, and a stored Curl runs as Slide")
    func noCurlInABook() {
        let reader = model()
        reader.choose(.pageCurl)

        let flat = reader.transitions(reduceMotion: false)
        let book = reader.transitions(reduceMotion: false, isBookPosture: true)

        #expect(flat.offered.contains(.pageCurl), "a flat display lost Curl: \(flat.offered)")
        #expect(!book.offered.contains(.pageCurl), "a book posture offered Curl: \(book.offered)")
        #expect(book.effective == .slide)
        #expect(book.chosen == .pageCurl, "the stored choice was overwritten")
    }

    /// The picker, the pager and the pairing each read ``ReaderView/transitions``, which is where
    /// the posture goes in. A call that went to the model directly would offer Curl in a book.
    @Test("Every reader surface asks for the transitions through the posture")
    func oneRouteToTheModel() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/ReaderFeature")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let callers = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("model.transitions(") }

        #expect(callers.map(\.lastPathComponent) == ["ReaderFold.swift"])
    }
}
