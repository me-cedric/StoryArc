internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// How many of a shelf's members are already on this device, out of how many it has.
///
/// `collections-and-reading-lists`' bulk download wants "the item count and total size
/// before starting", and the collection, list and series headers want the same count said
/// the other way round, before the reader ever asks to download anything: how much of this
/// is already here. A pure function beside the three headers that draw it, rather than a
/// rule written once inside each — the reason every other count in this module is split out
/// this way.
enum ShelfAvailability {
    /// Counts the members `onDevice` answers true for, out of the whole set.
    ///
    /// Takes the predicate rather than a `LibraryModel`, so a test can hand it publications
    /// of its own choosing without constructing one.
    static func onDeviceCount(
        of members: [Publication],
        onDevice: (Publication) -> Bool
    ) -> (onDevice: Int, total: Int) {
        (members.filter(onDevice).count, members.count)
    }
}

/// The sentence a collection, list or series header states from ``ShelfAvailability``'s count.
///
/// Its own view, drawn three times over, rather than a `Text` built inline in each header —
/// the three already disagree about font and colour, and a fourth copy of the interpolation
/// is where that drifts into a fourth wording.
struct ShelfOnDeviceLine: View {
    @Environment(\.theme) private var theme

    let onDevice: Int
    let total: Int

    /// For a collection or a series, where every member is a publication the library still
    /// holds — `total` is `members.count`.
    init(_ members: [Publication], model: LibraryModel) {
        let counted = ShelfAvailability.onDeviceCount(of: members) { publication in
            model.location(of: publication)?.isFileURL == true
        }
        self.onDevice = counted.onDevice
        self.total = counted.total
    }

    /// For a reading list, where an entry can outlive the publication it named —
    /// `collections-and-reading-lists`: it "remains in the list, marked unavailable". `total`
    /// is every entry; `members` is only the ones the library can still answer for, which is
    /// why it is asked separately rather than derived from `entries`.
    init(entries: [String], members: [Publication], model: LibraryModel) {
        let counted = ShelfAvailability.onDeviceCount(of: members) { publication in
            model.location(of: publication)?.isFileURL == true
        }
        self.onDevice = counted.onDevice
        self.total = entries.count
    }

    var body: some View {
        Text("shelves.onDevice \(onDevice) \(total)", bundle: .module)
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textSecondary)
    }
}
