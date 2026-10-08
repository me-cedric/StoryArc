internal import SwiftUI

internal import Kavita
internal import StoryArcCore

/// Asks, then writes a chosen cover back to its source, where the source takes one.
///
/// Whether the cover menu offers the row at all is ``CoverWriteBack/offer(for:)``'s answer
/// and nothing else, which is what task 5.2 of `cover-for-every-publication` guards: no screen
/// grows its own copy of the condition and starts offering a row that answers 403. See
/// ``KavitaListCover/menuRows(listID:hasChosen:lists:)``.
///
/// **The confirmation is not a formality.** A reading-list cover is the whole server's view
/// of that list, so the dialog says in those words that this changes the cover for everyone
/// who can see it.
///
/// A modifier on the screen rather than a button of its own: the row lives in the cover menu,
/// and a menu is gone the moment a row is chosen, with whatever was attached to it.
private struct CoverWriteBackDialog: ViewModifier {
    /// What the cover was set on, which decides whether anything is sent. Nil where the menu
    /// offers no such row.
    let subject: CoverWriteSubject?

    /// The chosen cover's bytes.
    ///
    /// **This is the seam onto the cover-override store.** Nil means no cover has been
    /// chosen, and nothing is sent: there is nothing to send.
    let image: () async -> Data?

    /// Sends the cover. Supplied by the screen that holds the server's client, because a
    /// view does not build one.
    let send: (Int, Data) async throws -> Void

    @Binding var asking: CoverMenuRow?

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Text("covers.writeBack", bundle: .module),
                isPresented: $asking.isAsking(.sendToServer),
                titleVisibility: .visible
            ) {
                if let subject, case let .kavitaReadingList(id) = CoverWriteBack.offer(for: subject) {
                    Button { Task { await write(to: id) } } label: {
                        Text("covers.writeBack.send", bundle: .module)
                    }
                }
            } message: {
                Text("covers.writeBack.body", bundle: .module)
            }
            .alert(
                Text("covers.writeBack", bundle: .module),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button { failure = nil } label: {
                    Text("library.import.dismiss", bundle: .module)
                }
            } message: {
                Text(failure ?? "")
            }
    }

    /// Sends the chosen cover, and says so in a sentence when the server refuses.
    ///
    /// A refusal here is loud, unlike a cover lookup's: the reader asked for this one.
    private func write(to id: Int) async {
        guard let data = await image() else { return }
        do {
            try await send(id, data)
        } catch let error as KavitaError {
            failure = KavitaConnection.describe(error)
        } catch {
            failure = KavitaConnection.describe(.unexpectedResponse)
        }
    }
}

extension View {
    func coverWriteBack(
        asking: Binding<CoverMenuRow?>,
        subject: CoverWriteSubject?,
        image: @escaping () async -> Data?,
        send: @escaping (Int, Data) async throws -> Void
    ) -> some View {
        modifier(CoverWriteBackDialog(subject: subject, image: image, send: send, asking: asking))
    }
}
