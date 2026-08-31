import Foundation
import Testing

/// That a downloaded solid archive opens like any other book.
///
/// `publication-formats`, *Streaming capability per format*:
///
/// > **WHEN** a publication that cannot stream is already available offline
/// > **THEN** it opens directly with no notice, because the constraint was never about the
/// > format being readable
///
/// **This is a guard against a notice arriving, not a proof that one is absent today.** No
/// solid-archive or streaming notice exists in either app to suppress, so nothing here can
/// measure a suppression: `StreamingOffer.of` answering `.open` for a local `.downloadOnly`
/// publication is the rule, and ``StreamingOfferTests`` asserts it. What was missing was
/// anything that fails the day somebody adds the notice, and a scenario nothing can fail is a
/// scenario nothing protects.
///
/// So the assertion is an absence, across the module that opens comics. The reader is handed a
/// URL and a `Publication`; it has no business reading how that publication was obtained. A
/// notice about the container would be gated on the capability, and would therefore have to
/// name it. Android keeps the same guard in `SolidArchiveHasNoNoticeTest.kt`.
@Suite("A publication that is already on the device opens with no notice")
struct SolidArchiveHasNoNoticeTests {

    /// Every Swift source in `ReaderFeature`, reached from this file rather than discovered.
    ///
    /// Built from `#filePath`, which is this test's own compiled path and therefore inside the
    /// package under test by construction. Walking up looking for a marker would leave it:
    /// this repository nests agent worktrees at `.claude/worktrees/<name>/`.
    private static let sources: [URL] = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tree = package.appending(path: "Sources/ReaderFeature")
        guard let walk = FileManager.default.enumerator(at: tree, includingPropertiesForKeys: nil)
        else {
            fatalError("Sources/ReaderFeature is not at \(tree.path) — has it moved?")
        }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }()

    /// What a notice about the container would have to mention to decide when to appear.
    ///
    /// `isSolid` and `isStreamable` are the format layer's own names for the two facts; the
    /// enum and the offer are how the rest of the app carries them.
    private static let noticeTells = [
        "StreamingCapability",
        "StreamingOffer",
        "downloadOnly",
        "isSolid",
        "isStreamable",
    ]

    @Test("The reader has sources to read")
    func thereAreSources() {
        // A guard over an empty list passes forever. This is the one assertion that fails if
        // the walk stops finding anything.
        #expect(Self.sources.count > 5, "No Swift sources found under Sources/ReaderFeature")
    }

    @Test("The reader says nothing about how a publication was obtained")
    func theReaderIsQuiet() {
        let offenders = Self.sources.filter { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
            return Self.noticeTells.contains { text.contains($0) }
        }
        #expect(
            offenders.isEmpty,
            """
            These files name a streaming capability: \(offenders.map(\.lastPathComponent)). A \
            publication that is on the device opens directly with no notice — \
            `publication-formats` says the constraint "was never about the format being \
            readable", and a solid RAR5 that has been downloaded is a comic like any other. If \
            a notice is genuinely wanted here, change the spec first and then this test.
            """
        )
    }
}
