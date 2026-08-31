public import Foundation

/// What the app may do with a publication it has just met, and what it owes the reader
/// before doing it.
///
/// `publication-formats`' *Streaming capability per format* says the app "SHALL know which
/// formats can be read remotely and SHALL be honest when one cannot". Its two remote
/// scenarios are the whole of this type:
///
/// > **WHEN a** publication cannot be read with ranged reads
/// > **THEN** the app says the format has to be downloaded before it can be read, states
/// > the size, and offers to download it
/// > **AND** it does not begin streaming badly and leave the user watching a stalled page
///
/// > **WHEN** a publication that cannot stream is already available offline
/// > **THEN** it opens directly with no notice, because the constraint was never about the
/// > format being readable
///
/// ``StreamingCapability`` was the *classification* those scenarios need, and each platform
/// read it in exactly one place: Android's `primaryActionOf`, on the publication's own page,
/// answered `NEEDS_DOWNLOAD` for a `downloadOnly` publication; iOS's `SmbBrowserView` branched
/// on `streaming != .refused` at the tap, which is the line this type replaced. Neither share
/// browser owed the reader anything for the answer: it copied the whole file across without
/// saying so and without naming a size, and handed a container no decoder will open to the
/// reader anyway once the copy landed. This is the answer that decides both, in one place, so
/// the two apps decide alike. Android keeps the same rule in `StreamingOffer.kt`.
public enum StreamingOffer: Sendable, Equatable {
    /// Read it where it lies. Also the answer for anything already on the device, which is
    /// the second scenario above: a downloaded solid archive opens with no notice, because
    /// there is nothing left to say about it.
    case open

    /// It cannot be read where it lies. The whole file has to come across first, and this is
    /// how big it is — `nil` only where nothing honest can be said about the length, which
    /// `offline-downloads` requires to be stated as an absence rather than as a zero.
    case download(bytes: Int64?)

    /// No decoder will open this, here or anywhere. A solid RAR4: transferring it changes
    /// nothing, so the transfer is not offered.
    case refuse

    /// The offer for one publication.
    ///
    /// - Parameters:
    ///   - streaming: what the container reported about itself.
    ///   - isLocal: whether the bytes are on this device already.
    ///   - readsWhereItLies: whether the decoder this format needs can work from a ranged
    ///     source rather than from a path. Platform truth, and deliberately a parameter:
    ///     libarchive wants a path and PDFKit wants a file on iOS, `PdfRenderer` wants a
    ///     descriptor on Android, and the two lists are not the same length. Ignored when
    ///     `isLocal`, where every decoder has what it wants.
    ///   - bytes: what the source states the file weighs.
    ///
    /// **Why ``StreamingCapability/refused`` is only believed when the bytes are local.**
    /// `PublicationIndexer.index(source:name:identity:decoderPath:)` returns a *record* with
    /// `refused` for a remote PDF, EPUB or CBR — meaning "its pages cannot be reached from
    /// here", not "no decoder will open it". Read as a refusal that would turn every remote
    /// comic in a RAR into a book the app declines to fetch. Once the file is local the
    /// value means what ``StreamingCapability/refused`` documents, and that is where it is
    /// acted on.
    public static func of(
        streaming: StreamingCapability,
        isLocal: Bool,
        readsWhereItLies: Bool,
        bytes: Int64?
    ) -> StreamingOffer {
        if isLocal { return streaming == .refused ? .refuse : .open }
        if streaming == .downloadOnly || !readsWhereItLies { return .download(bytes: bytes) }
        return .open
    }
}
