import SwiftUI

internal import DesignSystem

/// What a source shows when the app cannot reach it with what it has stored.
///
/// `sources` requires a source that has lost its credential to be marked `unauthorized`
/// "with an explanation and an action to enter a new key". This is the explanation half;
/// removing and re-adding the source is the action, and Settings is where it lives.
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
