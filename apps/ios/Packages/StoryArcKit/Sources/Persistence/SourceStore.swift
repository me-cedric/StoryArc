public import Foundation

public import StoryArcCore

/// The source registry, on disk.
///
/// `sources` requires the registry to be "ordered, persistent", and the order to survive
/// a launch. A JSON blob in `UserDefaults` for the same reason ``SettingsStore`` is one:
/// the whole registry is read together to draw one list, and a store that reads it key by
/// key would let two halves of it disagree.
///
/// **Connection state is not stored.** It describes a network right now, so a state read
/// back from disk would be a claim about the past. Every source loads as `.connecting`
/// and whatever probes it says otherwise, which is also the honest thing to show a reader
/// on a cold launch.
public struct SourceStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.sources"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func registry() -> SourceRegistry {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredRegistry.self, from: data)
        else { return SourceRegistry() }
        return stored.registry
    }

    public func save(_ registry: SourceRegistry) {
        guard let data = try? JSONEncoder().encode(StoredRegistry(registry)) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets every source. Used by a reset, and by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

/// What is actually written.
///
/// A separate shape rather than making `Source` `Codable`, because the durable fields and
/// the runtime ones are different sets and a `Codable` conformance would quietly carry a
/// stale connection state to disk.
private struct StoredRegistry: Codable {
    struct Entry: Codable {
        let id: UUID
        let displayName: String
        let kind: String
        let lastSuccessfulSync: Date?
        let credentialReference: String?
        let locator: String?
    }

    let sources: [Entry]
    let tombstones: [SourceTombstone]

    init(_ registry: SourceRegistry) {
        sources = registry.sources.map { source in
            Entry(
                id: source.id,
                displayName: source.displayName,
                kind: source.kind.rawValue,
                lastSuccessfulSync: source.lastSuccessfulSync,
                credentialReference: source.credentialReference,
                locator: source.locator
            )
        }
        tombstones = registry.tombstones
    }

    var registry: SourceRegistry {
        SourceRegistry(
            // A kind this build does not know is dropped rather than guessed at. A source
            // written by a newer version has a type this one cannot fetch from, and
            // showing it as a folder would be worse than not showing it.
            sources: sources.compactMap { entry in
                guard let kind = SourceKind(rawValue: entry.kind) else { return nil }
                return Source(
                    id: entry.id,
                    displayName: entry.displayName,
                    kind: kind,
                    lastSuccessfulSync: entry.lastSuccessfulSync,
                    credentialReference: entry.credentialReference,
                    locator: entry.locator
                )
            },
            tombstones: tombstones
        )
    }
}
