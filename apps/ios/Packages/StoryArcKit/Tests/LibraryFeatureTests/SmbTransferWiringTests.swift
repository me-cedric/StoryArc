import Foundation
import Testing

/// That the share browser still *asks* before it fetches a whole publication.
///
/// ``StreamingOfferTests`` pins the rule — what the app owes a reader for a publication it
/// cannot read where it lies. It cannot pin the wiring, and the wiring is where the defect
/// lived: `SmbBrowserView.open(_:)` fetched the entire file the moment `PublicationIndexer`
/// handed back a record, with `entry.length` already in hand and nothing said to the reader.
/// Putting that read back leaves `StreamingOffer` compiled, used elsewhere, and every one of
/// its own tests green.
///
/// **So this test reads the source text, and that is a deliberate second choice.** The honest
/// test drives the browser against a share and watches what crosses the wire, which needs a
/// server and a booted simulator; Android's `ReaderChromeWiringTest` reached the same answer
/// for the same reason and says so at greater length. A guard that runs beats a better one
/// that does not. It is a tripwire, not a proof: it says the fetch is behind the reader's
/// answer, never that the dialog rendered. Delete it the day `pnpm smb` and a simulator are
/// part of a suite that runs.
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

    @Test("The offer that does the deciding is the shared rule")
    func theOfferIsTheRule() {
        // Twice: once before anything is transferred, once against the local copy afterwards.
        let decisions = Self.source.components(separatedBy: "StreamingOffer.of(").count - 1
        #expect(
            decisions == 2,
            """
            SmbBrowserView should ask StreamingOffer twice — what to do with what it found on \
            the share, and whether what arrived can be opened. Found \(decisions).
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

    @Test("What arrives is judged before the reader is sent to it")
    func whatArrivesIsJudged() {
        guard let transfer = Self.source.range(of: "private func transfer(_ entry: SmbEntry)")
        else {
            Issue.record("SmbBrowserView no longer has transfer(_:)")
            return
        }
        let body = Self.source[transfer.lowerBound...]
        guard let decision = body.range(of: "StreamingOffer.of("),
              let opening = body.range(of: "onOpen(")
        else {
            Issue.record("transfer(_:) neither decides nor opens")
            return
        }
        // A solid RAR4 indexes as `refused` only once its bytes are local, so this order is
        // the whole of "does not hold for solid RAR4, which is refused whether local or
        // remote". Opening first is what used to send a reader who had waited for the file
        // to a reader that cannot render page one.
        #expect(
            decision.lowerBound < opening.lowerBound,
            "transfer(_:) opens the publication before asking whether it can be opened."
        )
    }
}
