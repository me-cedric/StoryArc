import Foundation
import Testing

@testable import ReaderFeature

/// ``NoticeStage`` — which of `network-share`'s two notices the reader is owed.
///
/// The rule the dismissal defect turned on: the notice used to hide for good once dismissed,
/// so a reader who dismissed the 2 s notice was never offered the download at 60 s. Android's
/// `NoticeStageTest` is the same table.
@Suite("Which network notice the reader is owed")
struct NoticeStageTests {
    @Test("A brief stall says nothing")
    func briefStallIsSilent() {
        #expect(NoticeStage.of(blocked: 1.9, dismissed: nil) == nil)
    }

    @Test("Past 2 s the notice shows, and past 60 s the offer")
    func stagesFollowTheClock() {
        #expect(NoticeStage.of(blocked: 2, dismissed: nil) == .brief)
        #expect(NoticeStage.of(blocked: 59, dismissed: nil) == .brief)
        #expect(NoticeStage.of(blocked: 60, dismissed: nil) == .long)
    }

    @Test("Dismissing the brief notice still lets the offer appear at 60 s")
    func dismissingTheBriefNoticeKeepsTheOffer() {
        #expect(NoticeStage.of(blocked: 30, dismissed: .brief) == nil)
        #expect(NoticeStage.of(blocked: 60, dismissed: .brief) == .long)
    }

    @Test("Dismissing the offer hides it until the trouble ends")
    func dismissingTheOfferHidesIt() {
        #expect(NoticeStage.of(blocked: 90, dismissed: .long) == nil)
    }
}

/// That ``NetworkNotice`` records the stage a dismissal was made on, and runs one copy at a
/// time. A view body is where both live, and no unit test can press its buttons, so this reads
/// the source text — the second choice `SmbTransferWiringTests` explains.
@Suite("The network notice's buttons")
struct NetworkNoticeWiringTests {
    private static let source: String = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: "Sources/ReaderFeature/NetworkNotice.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("NetworkNotice.swift is not at \(file.path) — has it moved?")
        }
        return text
    }()

    @Test("A dismissal records the stage it was made on")
    func dismissalRecordsTheStage() {
        #expect(Self.source.contains("dismissed = stage; onDismiss()"))
        #expect(Self.source.contains("NoticeStage.of(blocked: blocked, dismissed: dismissed)"))
    }

    @Test("A failed copy is said, and a second tap does not start a second copy")
    func downloadIsAnsweredOnce() {
        #expect(Self.source.contains("downloadFailed = !(await onDownload())"))
        #expect(Self.source.contains("if downloadFailed {"))
        #expect(Self.source.contains(".disabled(isCopying)"))
    }
}
