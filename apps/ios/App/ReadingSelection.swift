import Foundation

import StoryArcCore

/// One publication, chosen for reading.
///
/// Its own file rather than a tail on `StoryArcApp.swift`, which is at the 400-line cap:
/// the shell keeps growing and this is the piece of it that has nothing to do with the
/// scene.
struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
