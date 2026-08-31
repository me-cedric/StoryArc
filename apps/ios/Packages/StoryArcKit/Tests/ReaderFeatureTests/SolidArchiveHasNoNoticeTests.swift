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
/// So the assertion is an absence, across **both** modules that open a publication. The reader
/// is handed a URL and a `Publication`; it has no business reading how that publication was
/// obtained. A notice about the container would be gated on the capability, and would therefore
/// have to name it. Android keeps the same guard in `SolidArchiveHasNoNoticeTest.kt`, once per
/// reader module.
///
/// **Why the reflowable reader is walked from here.** The 5.3 note records the premise as
/// checked across `:feature:reader`, `:feature:epubreader` and iOS's `ReaderFeature`, and the
/// first version of this guard covered two of the three. `EpubReaderFeature` lives in the
/// sibling `StoryArcEpub` package, whose own test target needs a simulator — `pnpm test:ios`
/// runs `swift test` in `StoryArcKit` on the host and never reaches it. A guard that runs beats
/// a better one that does not, so this suite reaches across the package boundary instead. A
/// reflowable EPUB is also the publication most likely to be fetched whole before it opens, so
/// it is the likeliest home for a notice about how it got here.
@Suite("A publication that is already on the device opens with no notice")
struct SolidArchiveHasNoNoticeTests {

    /// Every Swift source in both readers, reached from this file rather than discovered.
    ///
    /// Built from `#filePath`, which is this test's own compiled path and therefore inside the
    /// package under test by construction. Walking up looking for a marker would leave it:
    /// this repository nests agent worktrees at `.claude/worktrees/<name>/`. `StoryArcEpub` is
    /// reached as `../StoryArcEpub` from that same anchor, which is where `Package.swift`
    /// declares it as a path dependency.
    private static let sources: [URL] = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let trees = [
            package.appending(path: "Sources/ReaderFeature"),
            package
                .deletingLastPathComponent()
                .appending(path: "StoryArcEpub/Sources/EpubReaderFeature"),
        ]
        return trees.flatMap { tree in
            guard let walk = FileManager.default.enumerator(
                at: tree, includingPropertiesForKeys: nil
            ) else {
                fatalError("\(tree.lastPathComponent) is not at \(tree.path) — has it moved?")
            }
            return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
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

    @Test("Both readers have sources to read")
    func thereAreSources() {
        // A guard over an empty list passes forever, and a guard over *one* of two trees
        // passes forever for the other. Both are named, so a missing one is a failure rather
        // than a quieter pass.
        #expect(Self.sources.count > 5, "No Swift sources found under either reader")
        // `/ReaderFeature/` does not match `/EpubReaderFeature/`, so the two are counted apart.
        #expect(
            Self.sources.contains { $0.path.contains("/ReaderFeature/") },
            "Nothing was walked in Sources/ReaderFeature — has it moved?"
        )
        #expect(
            Self.sources.contains { $0.path.contains("/EpubReaderFeature/") },
            "Nothing was walked in StoryArcEpub/Sources/EpubReaderFeature — has it moved?"
        )
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
