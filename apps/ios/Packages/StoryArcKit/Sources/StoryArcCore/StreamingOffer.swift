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
    /// **``StreamingCapability/refused`` is believed whether or not the bytes are local.**
    /// A solid RAR4 is refused "local or remote" — `RarComicArchive` detects it from the
    /// headers alone, with no file to hand a decoder, so the value is never a placeholder
    /// for "not checked yet". The bare record `PublicationIndexer.index(source:…)` returns
    /// for a remote PDF, EPUB or audio file with no local copy carries ``downloadOnly``
    /// rather than this, precisely so it never reaches this branch and gets read as a
    /// refusal that would decline to fetch the very publication the first scenario above
    /// is about.
    public static func of(
        streaming: StreamingCapability,
        isLocal: Bool,
        readsWhereItLies: Bool,
        bytes: Int64?
    ) -> StreamingOffer {
        if streaming == .refused { return .refuse }
        if isLocal { return .open }
        if streaming == .downloadOnly || !readsWhereItLies { return .download(bytes: bytes) }
        return .open
    }
}
