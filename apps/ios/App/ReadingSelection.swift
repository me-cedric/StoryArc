import Foundation
import StoryArcCore

/// One publication, chosen for reading.
///
/// The app layer owns this because a feature module never depends on another feature
/// module (docs/architecture) — the library reports a choice and the reader accepts one,
/// and neither knows the other exists.
struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
