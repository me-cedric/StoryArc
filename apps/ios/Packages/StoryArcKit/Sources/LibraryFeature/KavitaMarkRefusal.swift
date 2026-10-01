public import SwiftUI

/// D2: a read mark that a Kavita server cannot accept, until the reader dismisses the notice.
///
/// A server older than Kavita 0.9.0 has no `mark-multiple-*` route. ``KavitaSync`` removes
/// such a mark from its queue, and this tells the reader why. A mark comes from many screens,
/// so the shell shows the notice over the screen that is in front.
@MainActor
@Observable
public final class KavitaMarkRefusal {
    public static let shared = KavitaMarkRefusal()

    /// True after a server refused a mark, until the reader dismisses the notice.
    var isRefused = false

    public func note() { isRefused = true }
}

extension View {
    /// The notice for a refused mark. The shell attaches it once, over every tab.
    public func kavitaMarkRefusedNotice(from refusal: KavitaMarkRefusal) -> some View {
        alert(
            Text("kavita.mark.refused.title", bundle: .module),
            isPresented: Binding(
                get: { refusal.isRefused },
                set: { refusal.isRefused = $0 }
            )
        ) {
            Button { refusal.isRefused = false } label: {
                Text("library.import.dismiss", bundle: .module)
            }
        } message: {
            Text("kavita.mark.refused.body", bundle: .module)
        }
    }
}
