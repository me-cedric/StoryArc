import SwiftUI

internal import DesignSystem

/// What a source shows when the app cannot reach it with what it has stored.
///
/// `sources` requires a source that has lost its credential to be marked `unauthorized`
/// and offered "a single action to re-enter credentials, pre-filled with everything except
/// the secret". This is the explanation half, and it points at that action: the source's own
/// screen in Settings, which re-opens the sheet it was added through.
///
/// It used to point at "remove the source and add it again", which is what the audit called
/// out — that loses the source's place in the order, its downloads, and eventually the
/// reading positions its tombstone was holding.
struct UnreachableSource: View {
    @Environment(\.theme) private var theme

    let name: String

    /// Whether the server refused the key rather than the device having lost it.
    ///
    /// Two different facts and two different sentences. `kavita-server`'s revoked-key
    /// scenario is the first: the key is still in the keychain and the server no longer
    /// accepts it, so "this device no longer holds the key" would be telling the reader
    /// something untrue about their own device. Both lead to the same action.
    var isRefused = false

    var body: some View {
        ContentUnavailableView {
            Text("source.unauthorized.title", bundle: .module)
        } description: {
            if isRefused {
                Text("source.unauthorized.refused.body \(name)", bundle: .module)
            } else {
                Text("source.unauthorized.body \(name)", bundle: .module)
            }
        }
        .background(theme.palette.surfaceCanvas)
    }
}
