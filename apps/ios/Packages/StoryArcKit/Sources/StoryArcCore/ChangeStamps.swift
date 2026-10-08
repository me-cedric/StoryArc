public import Foundation

/// When a record or a field last changed, and on which device.
public struct DocumentStamp: Sendable, Equatable, Codable {
    public var at: Date
    public var by: String?

    public init(at: Date, by: String? = nil) {
        self.at = at
        self.by = by
    }
}

/// A shelf the reader deleted: its id, when, and on which device.
public struct DocumentTombstone: Sendable, Equatable, Codable {
    public var id: UUID
    public var removedAt: Date
    public var removedBy: String?

    public init(id: UUID, removedAt: Date, removedBy: String? = nil) {
        self.id = id
        self.removedAt = removedAt
        self.removedBy = removedBy
    }
}

/// One field a sync merges on its own: its name in the document, whether two values agree on
/// it, and how to take it from another value.
///
/// `library-sync` task 3.5: settings and themes merge last-writer-wins *per field*, so one
/// device's theme and another device's font size both survive. Android's `SyncField` lists the
/// same names.
public struct SyncField<Value> {
    public let name: String
    let same: (Value, Value) -> Bool
    let take: (inout Value, Value) -> Void

    init<T: Equatable>(_ name: String, _ path: WritableKeyPath<Value, T>) {
        self.name = name
        same = { $0[keyPath: path] == $1[keyPath: path] }
        take = { $0[keyPath: path] = $1[keyPath: path] }
    }

    init(_ name: String, same: @escaping (Value, Value) -> Bool, take: @escaping (inout Value, Value) -> Void) {
        self.name = name
        self.same = same
        self.take = take
    }
}

/// A value after a field merge, with the moment each field last changed.
public struct StampedValue<Value> {
    public var value: Value
    public var changedAt: [String: Date]
}

/// The moments a field changed: stamped by a store when the reader changes it, and compared
/// between two devices when a sync merges.
///
/// Moments are compared to the whole second, because the document writes them to the whole
/// second. Android's `ChangeStamps` holds the same rules.
public enum ChangeStamps {

    /// The moment a field counts as changed when nothing stamped it and it is not the default:
    /// changed before sync existed. One second, so it wins over a default and loses to any
    /// real stamp.
    public static let unknownChange: TimeInterval = 1

    /// A moment to the whole second, the resolution of the document.
    public static func seconds(_ date: Date) -> TimeInterval {
        date.timeIntervalSince1970.rounded(.down)
    }

    /// The fields that differ between two values, by name.
    static func changed<V>(_ fields: [SyncField<V>], _ before: V, _ after: V, prefix: String = "") -> [String] {
        fields.filter { !$0.same(before, after) }.map { prefix + $0.name }
    }

    /// The moments a store writes.
    ///
    /// A field whose value changed while its moment did not is a change the reader made, so
    /// it is stamped `now`. A field whose moment the caller changed keeps that moment. A sync
    /// does not come here: it writes the moments its merge decided as they are, because a
    /// value the merge took from another device is not a change this device made.
    public static func restamped(
        changed: [String],
        before beforeStamps: [String: Date],
        after afterStamps: [String: Date],
        now: Date
    ) -> [String: Date] {
        var stamps = afterStamps
        for name in changed where afterStamps[name] == beforeStamps[name] {
            stamps[name] = now
        }
        return stamps
    }

    /// Last writer wins, field by field.
    ///
    /// The newer moment takes the field. On the same second with two values, the device whose
    /// id sorts last wins, so two devices settle on one value instead of each keeping its own.
    ///
    /// - Parameter key: the name a field's moment is filed under, for a field inside an entry.
    static func merging<V>( // swiftlint:disable:this function_parameter_count
        _ fields: [SyncField<V>],
        default fallback: V,
        local: V,
        localStamps: [String: Date],
        remote: V,
        remoteStamps: [String: DocumentStamp],
        device: String,
        key: (String) -> String = { $0 }
    ) -> StampedValue<V> {
        var value = local
        var stamps: [String: Date] = [:]
        for field in fields {
            let name = key(field.name)
            let mine = localStamps[name].map(seconds) ?? unknown(field, local, fallback)
            let theirs = remoteStamps[name]
            let theirsAt = theirs.map { seconds($0.at) } ?? unknown(field, remote, fallback)
            let differ = !field.same(local, remote)
            let remoteWins = theirsAt > mine
                || (theirsAt == mine && theirsAt > 0 && differ && (theirs?.by ?? "") > device)
            if remoteWins {
                field.take(&value, remote)
                stamps[name] = Date(timeIntervalSince1970: theirsAt)
            } else if let held = localStamps[name] {
                stamps[name] = held
            }
        }
        return StampedValue(value: value, changedAt: stamps)
    }

    private static func unknown<V>(_ field: SyncField<V>, _ value: V, _ fallback: V) -> TimeInterval {
        field.same(value, fallback) ? 0 : unknownChange
    }

    /// The device to name beside a moment in the document: the previous document's when the
    /// moment is the one it already carried, because this device only took that change.
    static func by(_ at: Date, previousAt: Date?, previousBy: String?, device: String?) -> String? {
        if let previousBy, let previousAt, seconds(previousAt) == seconds(at) { return previousBy }
        return device
    }

    /// The document's stamps as moments this device keeps.
    static func moments(_ stamps: [String: DocumentStamp]?) -> [String: Date] {
        (stamps ?? [:]).mapValues(\.at)
    }

    /// Moments as the document writes them, each with the device that made it. Nil when there
    /// are none, so a document from a library with no stamps keeps its old bytes.
    static func documentStamps(
        _ moments: [String: Date],
        previous: [String: DocumentStamp]?,
        device: String?
    ) -> [String: DocumentStamp]? {
        guard !moments.isEmpty else { return nil }
        return moments.reduce(into: [:]) { stamps, pair in
            let before = previous?[pair.key]
            stamps[pair.key] = DocumentStamp(
                at: Date(timeIntervalSince1970: seconds(pair.value)),
                by: by(pair.value, previousAt: before?.at, previousBy: before?.by, device: device)
            )
        }
    }
}
