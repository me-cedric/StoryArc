import Foundation
import SwiftUI
import Synchronization

@testable import Persistence
@testable import SettingsFeature
import StoryArcCore

/// A secure store in memory.
final class HeldSecrets: SourceSecretStore {
    private let held = Mutex<[String: String]>([:])

    var contents: [String: String] { held.withLock { $0 } }

    func save(_ secret: String, for reference: String) -> Bool {
        held.withLock { $0[reference] = secret }
        return true
    }

    func secret(for reference: String) -> String? { held.withLock { $0[reference] } }

    func remove(_ reference: String) -> Bool {
        held.withLock { _ = $0.removeValue(forKey: reference) }
        return true
    }
}

/// One device for the transfer screens' tests: real stores in a private suite, a secure store in
/// memory, and the two libraries the tests move between them.
@MainActor
struct TransferDevice {
    static let shareID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    static let kavitaID = UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()

    let archive: LibraryArchive
    let secrets = HeldSecrets()
    let transfer: LibraryTransfer

    init() throws {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        archive = LibraryArchive(defaults: defaults, progress: try ProgressStore.inMemory())
        transfer = LibraryTransfer(archive: archive, secrets: secrets)
    }

    /// The library an export carries: a share and a server, each with a secret, a pinned
    /// certificate, and a collection.
    static var library: LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(
                    id: shareID,
                    displayName: "Comics NAS",
                    kind: .networkShare,
                    credentialReference: "share-handle",
                    locator: "smb://reader@nas.local/comics"
                ),
                Source(
                    id: kavitaID,
                    displayName: "Kavita",
                    kind: .kavitaServer,
                    credentialReference: "kavita-handle",
                    locator: "https://kavita.example/api?library=3"
                ),
            ]),
            certificatePins: ["nas.local": ["AB:CD"]],
            shelves: Shelves(collections: [
                PublicationCollection(name: "Image Comics", members: ["path:/a.cbz", "path:/b.cbz"]),
            ])
        )
    }

    /// This device holding `library`, with its secrets in the secure store.
    func holding(_ library: LibrarySnapshot = TransferDevice.library) async throws -> TransferDevice {
        _ = secrets.save("nas-password", for: "share-handle")
        _ = secrets.save("kavita-key", for: "kavita-handle")
        try await archive.apply(library)
        return self
    }

    /// A file on disk holding `bytes`, which a picker would hand over.
    static func file(holding bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "library-\(UUID().uuidString).json")
        try bytes.write(to: url)
        return url
    }
}

/// Every value a view holds, found by walking the view's own value and what it holds.
///
/// A host test cannot render a view, and does not need to: a `Text` made from a key holds the key.
/// What is asserted is what the view asks for, which is what the reader is shown. A `ForEach`
/// keeps its rows in a closure this cannot call, so a row that matters is a view of its own and
/// is asserted on its own.
@MainActor
func visited(in view: some View) -> [Any] {
    var found: [Any] = []
    var seen: Set<ObjectIdentifier> = []

    func walk(_ value: Any, depth: Int) {
        guard depth < 80 else { return }
        found.append(value)
        if type(of: value) == LocalizedStringKey.self { return }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class, !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
            return
        }
        for child in mirror.children { walk(child.value, depth: depth + 1) }
    }

    walk(view.body, depth: 0)
    return found
}

/// Every string key a view looks up.
@MainActor
func lookups(in view: some View) -> Set<String> {
    var keys: Set<String> = []
    for value in visited(in: view) where type(of: value) == LocalizedStringKey.self {
        for child in Mirror(reflecting: value).children where child.label == "key" {
            if let key = child.value as? String { keys.insert(key) }
        }
    }
    return keys
}

/// The values of one type a view holds.
@MainActor
func values<T>(of type: T.Type, in view: some View) -> [T] {
    visited(in: view).compactMap { $0 as? T }
}
