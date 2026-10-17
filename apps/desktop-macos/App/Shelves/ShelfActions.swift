import Foundation
import LibraryFeature
import Persistence
import StoryArcCore

/// Which shelves the reader pinned, kept where the phone keeps them (`PinnedShelves.storageKey`).
@MainActor
@Observable
final class ShelfPins {
    static let shared = ShelfPins()

    private(set) var pins: PinnedShelves
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pins = PinnedShelves(stored: defaults.string(forKey: PinnedShelves.storageKey) ?? "")
    }

    func toggle(_ pin: ShelfPin) {
        pins = pins.toggling(pin)
        defaults.set(pins.stored, forKey: PinnedShelves.storageKey)
    }

    func forget(_ pin: ShelfPin) {
        guard pins.contains(pin) else { return }
        toggle(pin)
    }
}

/// What the shelves' menus and pages do, through StoryArcKit's model and stores.
///
/// Creating, renaming, adding and ordering go through `LibraryModel`'s public calls. Deleting
/// a shelf and removing a collection's member are internal to the model, so they are written
/// to `ShelvesStore` (which stamps the deletion with its tombstone) and the model reads the
/// shelves back; a public call for them is a parent edit under `apps/ios`. Deleting a shelf
/// never deletes a publication, and the confirmation says so.
extension MacLibrary {
    var shelfRows: [ShelfRow] { MacShelves.sidebar(model.shelves, pins: ShelfPins.shared.pins) }

    @discardableResult
    func createShelf(_ kind: ShelfRow.Kind, named name: String, with ids: [String] = []) -> ShelfPin? {
        let before = Set(model.shelves.collections.map(\.id) + model.shelves.lists.map(\.id))
        switch kind {
        case .collection: model.create(collection: name)
        case .list: model.create(list: name)
        }
        let created = kind == .collection
            ? model.shelves.collections.first { !before.contains($0.id) }.map { ShelfPin.collection($0.id) }
            : model.shelves.lists.first { !before.contains($0.id) }.map { ShelfPin.list($0.id) }
        if let created, !ids.isEmpty { add(ids, to: created) }
        return created
    }

    func add(_ ids: [String], to pin: ShelfPin) {
        switch pin {
        case let .collection(id): model.add(Set(ids), toCollection: id)
        case let .list(id): model.append(ids, toList: id)
        case .server: break
        }
    }

    func rename(_ pin: ShelfPin, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch pin {
        case let .collection(id): model.rename(collection: id, to: trimmed)
        case let .list(id): model.rename(list: id, to: trimmed)
        case .server: break
        }
    }

    func deleteShelf(_ pin: ShelfPin) async {
        let shelves = model.shelves
        let after: Shelves
        switch pin {
        case let .collection(id): after = shelves.deleting(collection: id)
        case let .list(id): after = shelves.deleting(list: id)
        case .server: return
        }
        ShelvesStore().save(after)
        ShelfPins.shared.forget(pin)
        await model.reloadAfterImport()
    }

    func remove(_ id: String, from pin: ShelfPin) async {
        switch pin {
        case let .collection(collection):
            ShelvesStore().save(model.shelves.removing([id], from: collection))
            await model.reloadAfterImport()
        case let .list(list):
            model.remove(id, fromList: list)
        case .server:
            break
        }
    }

    func move(_ id: String, to position: Int, inList list: UUID) {
        model.move(id, to: position, inList: list)
    }
}
