internal import SwiftUI

internal import StoryArcCore

/// Which sentence the source detail screen states about how a source is reached.
///
/// `network-share`'s *Encrypted transport*: "the source detail screen states whether the
/// connection is encrypted". A share is the only kind with a transport to state. A folder is
/// a disk, and the two servers are reached over HTTP.
///
/// **Outside the view, because the view used to answer this with a fixed key.** The rule is a
/// function, the view calls it with what the last session negotiated, and a test can pass
/// each answer in and watch the drawn sentence follow.
///
/// Three whole sentences, one per state, never a clause added to another: French, German and
/// Spanish order the words differently. Two of them name the dialect the session agreed.
///
/// **It names encryption and never signing, and that is a decision rather than an omission.**
/// [ADR-0016](docs/decisions/0016-ios-smb-response-signing.md) refuses a signing line on iOS.
/// This screen is drawn the same way on both platforms, so a signed session reads like an
/// unsigned one here.
///
/// - Parameters:
///   - kind: what sort of source this is.
///   - transport: what the last session with this share negotiated, or `nil` when the app
///     has not reached it since it started.
/// - Returns: the key to draw, or `nil` when this kind of source has no transport to state.
func transportNote(for kind: SourceKind, transport: ShareTransport?) -> LocalizedStringKey? {
    guard kind == .networkShare else { return nil }
    guard let transport else { return "sources.detail.transport.unknown" }
    return transport.isEncrypted
        ? "sources.detail.transport.encrypted \(transport.dialect)"
        : "sources.detail.transport.plain \(transport.dialect)"
}
