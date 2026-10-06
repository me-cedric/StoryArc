internal import SwiftUI

internal import Kavita
internal import StoryArcCore

/// Offers to write a chosen cover back to its source, where the source takes one.
///
/// The offer is ``CoverWriteBack/offer(for:)``'s answer and nothing else, which is what
/// task 5.2 of `cover-for-every-publication` guards: no screen grows its own copy of the
/// condition and starts offering a button that answers 403.
///
/// **The confirmation is not a formality.** A reading-list cover is the whole server's view
/// of that list, so the dialog says in those words that this changes the cover for everyone
/// who can see it.
struct CoverWriteBackButton: View {
    /// What the cover was set on, which decides whether anything is drawn at all.
    let subject: CoverWriteSubject

    /// The chosen cover's bytes.
    ///
    /// **This is the seam onto the cover-override store.** Sections 1 and 2 of this change
    /// own that store and the one point that resolves a cover; this button is given the
    /// bytes rather than reaching for them, so the two halves join at one closure. Nil means
    /// no cover has been chosen, and nothing is offered: there is nothing to send.
    let image: () async -> Data?

    /// Sends the cover. Supplied by the screen that holds the server's client, because a
    /// view does not build one.
    let send: (Int, Data) async throws -> Void

    @State private var isConfirming = false

    @State private var failure: String?

    var body: some View {
        if case let .kavitaReadingList(id) = CoverWriteBack.offer(for: subject) {
            Button { isConfirming = true } label: {
                Text("covers.writeBack", bundle: .module)
            }
            .confirmationDialog(
                Text("covers.writeBack", bundle: .module),
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button { Task { await write(to: id) } } label: {
                    Text("covers.writeBack.send", bundle: .module)
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
