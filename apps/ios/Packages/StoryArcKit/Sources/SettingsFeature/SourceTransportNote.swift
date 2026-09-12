internal import SwiftUI

internal import StoryArcCore

/// Which sentence the source detail screen states about how a source is reached.
///
/// `network-share`'s *Encrypted transport*: "the source detail screen states whether the
/// connection is encrypted". A share is the only kind with a transport to state. A folder is
/// a disk, and the two servers are reached over HTTP.
///
/// **Outside the view, because the view used to answer this with a fixed key.** The sentence
/// said the connection is not encrypted whatever the code had measured, so a test that drew
/// the screen and read the sentence back agreed with itself and proved nothing. The rule is a
/// function now, the view calls it with the measured value, and a test can pass both answers
/// in and watch the drawn sentence follow.
///
/// **It names encryption and never signing, and that is a decision rather than an omission.**
/// [ADR-0016](docs/decisions/0016-ios-smb-response-signing.md) refuses a signing line on iOS,
/// because this client verifies no response and cannot answer the question. Android's client
/// can answer it, and its add-share sheet says so. This screen is drawn the same way on both
/// platforms, so a signed session reads like an unsigned one here.
///
/// - Parameters:
///   - kind: what sort of source this is.
///   - isEncrypted: what the app measured, which is ``StoryArcCore/ShareTransport/isEncrypted``
///     today.
/// - Returns: the key to draw, or `nil` when this kind of source has no transport to state.
func transportNote(for kind: SourceKind, isEncrypted: Bool) -> LocalizedStringKey? {
    guard kind == .networkShare else { return nil }
    return isEncrypted ? "sources.detail.transport.encrypted" : "sources.detail.transport.plain"
}
