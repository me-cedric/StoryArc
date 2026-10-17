import LibraryFeature
import StoryArcCore
import SwiftUI

/// A *Start from the Beginning* the reader chose from a cover's menu, waiting to be confirmed.
///
/// `reading-progress`, *Restart deliberately*: the action is on the cover's own menu, which
/// every browse surface carries, offered only on one publication with a position to clear,
/// and it clears the position only after confirmation. The rule is `LibraryFeature`'s
/// `RestartOffer`; the confirmation and the clearing are the Mac's, because the iOS dialog
/// and `LibraryModel.restart` are internal to the package.
struct RestartRequest: Equatable {
    let publication: Publication

    /// Whether the menu offers it for this publication.
    static func isOffered(hasProgress: Bool, selectionCount: Int, hasStore: Bool) -> Bool {
        RestartOffer.isOffered(publicationCount: selectionCount, hasSomethingToClear: hasProgress, isWired: hasStore)
    }

    /// How many publications a cover's menu acts on: the whole selection when the clicked
    /// cover is part of it, as a Mac context menu does, and the clicked cover alone otherwise.
    static func menuCount(for id: String, in selection: LibrarySelection) -> Int {
        selection.contains(id) ? max(1, selection.count) : 1
    }
}

extension MacLibrary {
    func requestRestart(_ publication: Publication) {
        restartRequest = RestartRequest(publication: publication)
    }

    func cancelRestart() {
        restartRequest = nil
    }

    /// Forgets the position, so the next open starts at page one. Forgetting rather than
    /// rewinding, as `LibraryModel.restart` does: a record set back to page one would still
    /// say the publication had been opened.
    func confirmRestart() async {
        guard let request = restartRequest else { return }
        restartRequest = nil
        try? await progress?.forget(request.publication.identity)
        await refreshProgress()
    }
}

extension View {
    /// The confirmation the library window shows for a pending restart.
    func restartConfirmation(_ library: MacLibrary) -> some View {
        confirmationDialog(
            Text("desktop.restart.title \(library.restartRequest?.publication.displayTitle ?? "")"),
            isPresented: Binding(
                get: { library.restartRequest != nil },
                set: { if !$0 { library.cancelRestart() } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await library.confirmRestart() }
            } label: {
                Text("desktop.restart.confirm")
            }
            Button(role: .cancel) { library.cancelRestart() } label: { Text("desktop.drop.folder.cancel") }
        } message: {
            Text("desktop.restart.body")
        }
    }
}
