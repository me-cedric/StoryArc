import Foundation
import Testing

/// That the share browser still *asks* before it fetches a whole publication, and still routes
/// both decisions through the pair a test can drive.
///
/// ``StreamingOfferTests`` pins the rule — what the app owes a reader for a publication it
/// cannot read where it lies. ``ShareOpeningTests`` pins what the browser feeds that rule and
/// what it does with the answer, by calling `ShareOpening.offerOrOpen` and
/// `ShareOpening.openWhatArrived` directly. Neither can pin the wiring, and the wiring is where
/// the defect lived: `SmbBrowserView.open(_:)` fetched the entire file the moment
/// `PublicationIndexer` handed back a record, with `entry.length` already in hand and nothing
/// said to the reader.
///
/// **So this test reads the source text, and that is a deliberate second choice.** The honest
/// test drives the browser against a share and watches what crosses the wire, which needs a
/// server and a booted simulator; Android's `ReaderChromeWiringTest` reached the same answer
/// for the same reason and says so at greater length. A guard that runs beats a better one
/// that does not. Delete it the day `pnpm smb` and a simulator are part of a suite that runs.
///
/// **What it is allowed to assert, and what it is not.** Its earlier form claimed to check that
/// "what arrives is judged before the reader is sent to it" and actually checked that
/// `StreamingOffer.of(` appeared before `onOpen(` in the file. Replacing the judgement with
/// `_ = offer; onOpen(publication, local)` kept that order and passed. Textual order is not a
/// behaviour, so the behaviour is asserted in ``ShareOpeningTests`` and what is left here is
/// the one thing text can honestly say: that the view delegates instead of deciding for
/// itself.
@Suite("The share browser offers the transfer rather than taking it")
struct SmbTransferWiringTests {

    /// The browser's source, reached from this file rather than discovered.
    ///
    /// Built from `#filePath`, which is this test's own compiled path and therefore inside
    /// the package under test by construction. Walking up looking for a marker would leave
    /// it: this repository nests agent worktrees at `.claude/worktrees/<name>/`, so a walk
    /// climbs out of the checkout being built and reads the parent's copy of a file that was
    /// never compiled here.
    private static let source: String = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: "Sources/LibraryFeature/SmbBrowserView.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("SmbBrowserView.swift is not at \(file.path) — has it moved?")
        }
        return text
    }()

    /// Everything from `open(_:)` up to the next declaration: the path a tap takes before the
    /// reader has answered anything.
    private static let openBody: Substring = {
        guard let start = source.range(of: "private func open(_ entry: SmbEntry) async"),
              let end = source.range(of: "private func transfer(_ entry: SmbEntry) async")
        else {
            fatalError("SmbBrowserView no longer has both open(_:) and transfer(_:)")
        }
        return source[start.lowerBound..<end.lowerBound]
    }()

    @Test("A tap on a share does not read the whole file")
    func tappingTransfersNothing() {
        // The regression, exactly: a whole-file read reachable from the tap. `network-share`
        // asks the first page of a 400 MB comic to cost megabytes, and `publication-formats`
        // asks for the offer to be made before the ones that cannot.
        #expect(
            !Self.openBody.contains("source.read(offset: 0"),
            """
            SmbBrowserView.open(_:) reads the whole file again. The transfer belongs behind \
            the reader's answer to smb.downloadFirst.title — `publication-formats` requires \
            the app to state the size "and offer to download it", not to take it.
            """
        )
    }

    @Test("Both decisions go through the pair that is tested")
    func bothDecisionsAreDelegated() {
        // Once for what was found on the share, once for what arrived from it. Deciding
        // inline again is what put the judgement somewhere only a text search could reach.
        #expect(
            Self.source.components(separatedBy: "ShareOpening.offerOrOpen(").count - 1 == 1,
            "The tap should reach ShareOpening.offerOrOpen, which ShareOpeningTests drives."
        )
        #expect(
            Self.source.components(separatedBy: "ShareOpening.openWhatArrived(").count - 1 == 1,
            """
            The transfer's answer should reach ShareOpening.openWhatArrived, which \
            ShareOpeningTests drives.
            """
        )
    }

    @Test("The browser never opens a publication it decided about itself")
    func theViewDoesNotOpenAnything() {
        // The mutation this test exists for: calling `onOpen(publication, local)` from the
        // view bypasses the tested decision entirely, and ``ShareOpeningTests`` would stay
        // green because the function it drives is still correct. `onOpen: onOpen` as an
        // argument is not a call and does not match.
        #expect(
            !Self.source.contains("onOpen("),
            """
            SmbBrowserView invokes onOpen itself. Opening belongs to ShareOpening.offerOrOpen \
            and ShareOpening.openWhatArrived, which judge the publication first — see \
            ShareOpeningTests.
            """
        )
    }

    @Test("The size is stated before the transfer is agreed to")
    func theSizeIsStated() {
        #expect(Self.source.contains("smb.downloadFirst.body"))
        #expect(
            Self.source.contains("formattedBytes("),
            """
            The dialog must state the size the share reported. A figure is what \
            `publication-formats` asks for; the platform's own byte formatter is what the \
            Downloads destination and the metered confirmation already use.
            """
        )
    }

    @Test("A share that stated no size has a sentence of its own")
    func theUnstatedSizeIsSaid() {
        // `offline-downloads` asks for an absence rather than a zero, and `formattedBytes`
        // takes a non-optional — so without this branch a zero-length entry reads as a zero.
        #expect(
            Self.source.contains("smb.downloadFirst.bodyUnstated"),
            """
            The download offer must have the second body the metered confirmation already \
            has, for the entry whose length the share did not state.
            """
        )
    }
}
