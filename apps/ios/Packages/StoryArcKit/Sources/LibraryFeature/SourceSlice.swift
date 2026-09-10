internal import Foundation

internal import StoryArcCore

/// What one source put on the shelf, and whether it holds more than that.
///
/// **The number the source screen states is a slice, and it used to be stated as a total.**
/// Every contributor reads a bounded first helping — sixty series from a Kavita server, one
/// feed page from a catalogue, two hundred files or forty listings from a share — because a
/// library that walked a whole server before drawing anything would leave a reader looking
/// at nothing. `sources` asks the detail screen for the source's "cached item count", and
/// "cached" is the operative word: a reader whose server holds five thousand titles saw
/// "137 titles" and had no way to tell that from a server that holds 137.
///
/// ``holdsMore`` is a *statement about the read*, not about the source: it says the read
/// stopped at its own limit rather than at the end of the source. Android's `SourceSlice`
/// is the twin.
struct SourceSlice {
    let publications: [Publication]
    let holdsMore: Bool

    /// A read that reached the end of what the source has.
    static func whole(_ publications: [Publication]) -> SourceSlice {
        SourceSlice(publications: publications, holdsMore: false)
    }

    /// Nothing at all, from a source that refused or was not configured.
    static let none = SourceSlice(publications: [], holdsMore: false)
}
