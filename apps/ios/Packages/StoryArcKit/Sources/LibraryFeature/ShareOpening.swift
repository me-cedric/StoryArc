internal import Foundation
internal import StoryArcCore

/// What the share browser does about one publication, decided outside the view.
///
/// `SmbBrowserView` used to hold both decisions inline, and a text-reading tripwire is all a
/// suite with no simulator can say about a SwiftUI view: ``SmbTransferWiringTests`` could
/// assert that `StreamingOffer.of(` appears before `onOpen(` inside `transfer(_:)`, never that
/// the answer was acted on. Replacing the judgement with `_ = offer; onOpen(publication, local)`
/// kept that order and every test green — which is the defect this change exists to fix, back
/// with a passing suite. These two functions are the same decisions with the callbacks passed
/// in, so ``ShareOpeningTests`` can drive them with a publication of its choosing and watch
/// which one fires. Android keeps the same pair in `ShareOpening.kt`.
///
/// The view keeps what only it can do: which state a callback writes to, and which dialog that
/// state raises.
///
/// `@MainActor` because the callbacks are: they write `@State` on a SwiftUI view, and handing a
/// main-actor closure to a nonisolated function is a data race the compiler refuses. Returning
/// an answer for the view to switch on would avoid the annotation and give back the defect —
/// the switch would be back inside the view, where only a text search can reach it.
@MainActor
enum ShareOpening {

    /// Whether a format's decoder insists on a file of its own.
    ///
    /// PDFKit wants a file, libarchive wants a path, and the EPUB reader opens a file of its
    /// own — so those three are offered as a download and everything else is read where it
    /// lies.
    ///
    /// The platform half of ``StreamingOffer``'s `readsWhereItLies`, and deliberately stated
    /// as a fact about decoders rather than derived from what the container reported. The
    /// derivation it replaces — `catalogued.streaming != .refused` — happened to give the
    /// same three formats, because `PublicationIndexer.index(source:name:identity:)` returns a
    /// record marked `refused` for exactly them. That is a coincidence of two lists rather
    /// than one fact: `refused` means "no decoder will open this" everywhere else in the app,
    /// and reading it here as "this decoder wants a file" is how a *streaming* sentence came
    /// to be built out of it. Android's list is shorter — its EPUB reader takes a source.
    static func needsLocalFile(_ format: PublicationFormat) -> Bool {
        switch format {
        case .pdf, .epub, .cbr: true
        default: false
        }
    }

    /// What the share said the file weighs, or `nil` when it said nothing worth repeating.
    ///
    /// A directory entry's length is an `Int64` and a share always fills one in, so the honest
    /// absence ``StreamingOffer/download(bytes:)`` carries would otherwise be unreachable from
    /// here — and the value that does arrive for an entry the server declined to size is zero.
    /// `Zero bytes` in a download offer reads as a free download, which is exactly what
    /// `offline-downloads` means by requiring an absence "rather than as a zero".
    static func statedLength(_ length: Int64) -> Int64? { length > 0 ? length : nil }

    /// The refusal `publication-formats` requires to be named rather than retried.
    ///
    /// Built here rather than in the view, so that the decision owns the sentence it leads to
    /// and ``ShareOpeningTests`` can assert *which* sentence a publication earns. Android
    /// passes a string resource id for the same reason.
    static let cannotOpen = LocalizedStringResource(
        "smb.cannotOpen", bundle: .atURL(Bundle.module.bundleURL)
    )

    /// Said out loud rather than swallowed. A tap that does nothing is the worst answer a
    /// screen can give.
    static let unexpected = LocalizedStringResource(
        "smb.error.unexpected", bundle: .atURL(Bundle.module.bundleURL)
    )

    /// Indexes a publication on the share and does what ``StreamingOffer`` says about it.
    ///
    /// Nothing is transferred here: `index` reads headers over the share, which is what lets
    /// the caller state a size while it asks whether the transfer may happen at all.
    ///
    /// The ``cannotOpen`` branch is unreachable while the bytes are remote and is wired
    /// anyway — see ``StreamingOffer/of(streaming:isLocal:readsWhereItLies:bytes:)``, which
    /// only believes `refused` once a file exists to judge. A solid RAR4 on a share therefore
    /// costs a whole transfer before the app can say it cannot be opened, because libarchive
    /// reads `FHD_SOLID` through a path and nothing over the share can.
    static func offerOrOpen(
        index: () async throws -> (Publication, URL),
        length: Int64,
        onOpen: (Publication, URL) -> Void,
        onOffer: (Int64?) -> Void,
        onSay: (LocalizedStringResource) -> Void
    ) async {
        do {
            let (publication, remote) = try await index()
            switch StreamingOffer.of(
                streaming: publication.streaming,
                isLocal: false,
                readsWhereItLies: !needsLocalFile(publication.format),
                bytes: statedLength(length)
            ) {
            case .open: onOpen(publication, remote)
            case .download(let bytes): onOffer(bytes)
            case .refuse: onSay(cannotOpen)
            }
        } catch {
            onSay(unexpected)
        }
    }

    /// Judges what came back from a completed transfer, then opens it or refuses it.
    ///
    /// The first moment the container can say what it really is: a solid RAR5 becomes
    /// ``StreamingCapability/downloadOnly`` and opens, a solid RAR4 becomes
    /// ``StreamingCapability/refused`` and does not. The browser used to open whatever came
    /// back, so a reader who had just waited for four hundred megabytes was taken to a reader
    /// that could not render page one.
    ///
    /// `bytes` is `nil` rather than the entry's length: the bytes are local, so the answer is
    /// `open` or `refuse` and neither states a size.
    static func openWhatArrived(
        fetch: () async throws -> (Publication, URL),
        onOpen: (Publication, URL) -> Void,
        onSay: (LocalizedStringResource) -> Void
    ) async {
        do {
            let (publication, local) = try await fetch()
            let offer = StreamingOffer.of(
                streaming: publication.streaming,
                isLocal: true,
                readsWhereItLies: true,
                bytes: nil
            )
            if offer == .refuse { onSay(cannotOpen) } else { onOpen(publication, local) }
        } catch {
            onSay(unexpected)
        }
    }
}
