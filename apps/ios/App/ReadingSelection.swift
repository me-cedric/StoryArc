import Foundation

import StoryArcCore

/// One publication, chosen for reading.
///
/// The app layer owns this because a feature module never depends on another feature
/// module (docs/architecture) — the library reports a choice and the reader accepts one,
/// and neither knows the other exists.
///
/// Its own file rather than a tail on `StoryArcApp.swift`, which is where that wiring lives
/// and had grown past the length the linter allows. `OpenedFile` and `RefusedFile` are
/// already separate for the same reason.
struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
