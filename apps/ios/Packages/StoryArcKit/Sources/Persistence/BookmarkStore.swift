public import Foundation

public import StoryArcCore

/// Bookmarks, on disk, keyed by the publication they are in.
///
/// A JSON blob in `UserDefaults`, for the reason ``ShelvesStore`` is one: one publication's
/// marks are read together to draw one list, and a store that read them piecemeal would let
/// two halves of that list disagree.
///
/// Not in the caches directory, unlike ``LibraryCache``. A bookmark is something a reader
/// made; losing it costs them work rather than costing a rescan, so it belongs with the
/// reading position and not with the things the system may reclaim.
///
/// Android's `BookmarkStore` writes the same shape.
public struct BookmarkStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.bookmarks"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every mark in one publication, in book order.
    public func bookmarks(for publication: String) -> [Bookmark] {
        (stored()[publication] ?? []).inReadingOrder
    }

    /// Adds a mark, or removes the one already on that page.
    ///
    /// One control rather than two. A reader who presses it on a page they have already
    /// marked means "no longer", and a second identical entry in the list would be the
    /// button refusing to answer that.
    ///
    /// Returns what the publication holds afterwards, so a caller does not have to read
    /// back what it just wrote.
    @discardableResult
    public func toggle(_ bookmark: Bookmark, in publication: String) -> [Bookmark] {
        var all = stored()
        var marks = all[publication] ?? []
        if let existing = marks.mark(at: bookmark.progression, in: bookmark.resource) {
            marks.removeAll { $0.id == existing.id }
        } else {
            marks.append(bookmark)
        }
        all[publication] = marks.isEmpty ? nil : marks
        write(all)
        return marks.inReadingOrder
    }

    /// Removes one mark by identity, which is what the list offers.
    @discardableResult
    public func remove(_ id: UUID, from publication: String) -> [Bookmark] {
        var all = stored()
        var marks = all[publication] ?? []
        marks.removeAll { $0.id == id }
        all[publication] = marks.isEmpty ? nil : marks
        write(all)
        return marks.inReadingOrder
    }

    /// Forgets one publication's marks. What removing a publication takes with it.
    public func clear(_ publication: String) {
        var all = stored()
        all[publication] = nil
        write(all)
    }

    /// Forgets everything. The Privacy screen's reading history, and the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private func stored() -> [String: [Bookmark]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [Bookmark]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ all: [String: [Bookmark]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}
