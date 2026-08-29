public import Foundation

public import StoryArcCore

/// Highlights and notes, on disk, keyed by the publication they are in.
///
/// A JSON blob in `UserDefaults`, for the reason ``BookmarkStore`` is one: one publication's
/// marks are read together to draw one list, and a store that read them piecemeal would let
/// two halves of that list disagree.
///
/// Not in the caches directory. What a reader wrote is the least replaceable thing this app
/// holds — a lost highlight is not a rescan, it is a passage they will not find again.
///
/// Android's `AnnotationStore` writes the same shape.
public struct AnnotationStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.annotations"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every mark in one publication, in book order.
    public func annotations(for publication: String) -> [Annotation] {
        (stored()[publication] ?? []).inReadingOrder
    }

    /// Adds a mark, or replaces the one with the same identity.
    ///
    /// One method rather than an add beside an update, because editing a note is the same
    /// act as making one: the reader has something to say about those words.
    @discardableResult
    public func save(_ annotation: Annotation, in publication: String) -> [Annotation] {
        var all = stored()
        var marks = all[publication] ?? []
        if let index = marks.firstIndex(where: { $0.id == annotation.id }) {
            marks[index] = annotation
        } else {
            marks.append(annotation)
        }
        all[publication] = marks
        write(all)
        return marks.inReadingOrder
    }

    @discardableResult
    public func remove(_ id: UUID, from publication: String) -> [Annotation] {
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

    private func stored() -> [String: [Annotation]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [Annotation]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ all: [String: [Annotation]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}
