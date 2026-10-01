internal import Foundation

internal import StoryArcCore

/// What a reading list's row draws beneath its title, and what it says to a screen reader.
///
/// `collections-and-reading-lists`' delta: "each entry states its own read state — finished,
/// part-read with the position reached, or unread — in the same terms the library uses for a
/// publication". Free of the view so a test can call it directly, and shared in shape with
/// Android's `entryReadState` even though each platform reaches its own strings for it.
///
/// An unread entry draws nothing, the rule the library's own grid cell and
/// ``KavitaShelfViews``' server row both already keep — nothing on a shelf says "unread" out
/// loud through a badge. ``spoken`` still names it, since a screen reader is told what a
/// sighted reader would see by its absence.
struct ReadingListRowState: Equatable {
    /// What is drawn beneath the title, or nil to draw nothing.
    let drawn: String?
    /// What a screen reader is told, which never withholds "unread" the way `drawn` does.
    let spoken: String

    static func of(isAvailable: Bool, isFinished: Bool, fraction: Double?) -> ReadingListRowState {
        guard isAvailable else {
            return ReadingListRowState(
                drawn: nil,
                spoken: String(localized: "shelves.list.unavailable", bundle: .module, locale: .storyArc)
            )
        }
        let drawn: String? =
            if isFinished {
                String(localized: "library.cell.finished", bundle: .module, locale: .storyArc)
            } else if let fraction {
                String(
                    localized: "library.cell.progress \(Int(fraction * 100))",
                    bundle: .module,
                    locale: .storyArc
                )
            } else {
                nil
            }
        let spoken = drawn ?? String(
            localized: "library.readState.unread",
            bundle: .module,
            locale: .storyArc
        )
        return ReadingListRowState(drawn: drawn, spoken: spoken)
    }

    /// The row's merged label: its place in the list, its title and its read state, in the
    /// shape ``KavitaListView``'s own row speaks. The place is the one thing the label must
    /// not drop, because the order is what a reading list means.
    func spokenRow(number: Int, title: String) -> String {
        ["\(number).", title, spoken].joined(separator: " ")
    }
}
