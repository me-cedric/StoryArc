internal import StoryArcCore

/// The rows a car draws, as a value.
///
/// `audio-playback`'s "Listening in a car" asks a car surface for the book in progress
/// first, then the audiobooks on the device, flat, and nothing else. Android answers the
/// same requirement from `CarShelf` in `:core:playback`, asserted by `CarLibraryTest`.
/// This is the iOS half that needs neither a car nor a CarPlay entitlement, so it is the
/// half a host suite can run.
///
/// **The two platforms differ in mechanism and agree on content**, which is what
/// `design.md`'s "How a car gets a list, when the playback module has no library" records.
/// Android's service is started without the app, so it reads a preferences file the app
/// published; iOS builds its list when the CarPlay scene connects, by which time the app
/// is running, so the app hands the rows over directly.
///
/// A row is a ``SpokenBook`` rather than a type of its own. That is the value the player
/// already carries, its ``SpokenBook/label`` already states the two strings a car row
/// shows, and a second shape for the same fact is a second chance to disagree about what
/// a book is called.
public enum CarShelf {

    /// The book in progress first, then each audiobook on the device once.
    ///
    /// **The shelf is filtered to audio and the book in progress is not.** A car screen is
    /// not a place to browse comics, so a comic never reaches the shelf. A read-aloud
    /// session is a publication a listener can be in the middle of, and the requirement
    /// offers "audiobooks and read-aloud sessions" — so dropping a spoken EPUB from the
    /// first row would withhold the one row the listener asked for. Android draws the same
    /// line in the same place.
    ///
    /// Deduplicated by publication, so the book in progress is offered once rather than
    /// twice, and it keeps the first row because that is the row a listener reaches for.
    ///
    /// The position is not carried here. `audio-playback` asks the car for the book "with
    /// its position kept", and on iOS the app starts playback through the same seam a
    /// cover uses, which already resumes where the listener left off.
    public static func rows(continuing playing: SpokenBook?, onDevice shelf: [SpokenBook]) -> [SpokenBook] {
        let offered = (playing.map { [$0] } ?? []) + shelf.filter { $0.publication.format.isAudio }
        var seen = Set<String>()
        return offered.filter { seen.insert($0.id).inserted }
    }
}
