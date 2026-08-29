import Foundation

import StoryArcCore

/// One publication, chosen for reading.
///
/// Its own file rather than a tail on `StoryArcApp.swift`, which is where the app's own
/// wiring lives and had grown past the length the linter allows. `OpenedFile` and
/// `RefusedFile` are already separate for the same reason.
struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
