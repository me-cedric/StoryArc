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

    var body: some View {
        ContentUnavailableView {
            Text("source.unauthorized.title", bundle: .module)
        } description: {
            Text("source.unauthorized.body \(name)", bundle: .module)
        }
        .background(theme.palette.surfaceCanvas)
    }
}
