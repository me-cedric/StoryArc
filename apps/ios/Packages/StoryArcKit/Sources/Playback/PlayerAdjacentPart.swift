// Task 16.3, split out of `PlayerCentre.swift` at its line cap (AGENTS.md §5) the way
// `PlayerDisplacement.swift` already is: a seam the centre owns but a car or a lock screen
// reaches through one function, not the engine's own concern.
public extension PlayerCentre {

    /// The chapter move next-track and previous-track send, beside the seconds skip the
    /// other two buttons send. See ``TransportCommands``. Ignored past the first or last
    /// part: ``play(part:offset:)`` already guards the index.
    func moveToAdjacentPart(_ direction: SkipDirection) {
        play(part: place.partIndex + (direction == .forward ? 1 : -1))
    }
}
