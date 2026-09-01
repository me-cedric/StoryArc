/// The publications a scan could not open, and whether the reader has been told about them.
///
/// `library-browsing`'s *What could not be opened*: the library "SHALL say **which**
/// publications it could not open, not how many, and SHALL let a reader reach the reason".
///
/// **Nothing new is produced here.** `LibraryScanner` has always emitted the pair —
/// `ScanEvent.skipped(path:reason:)`, with the reason `publication-formats` words for that
/// refusal — and the library kept the tally and dropped the rest, so a scan that met a
/// 7-Zip container and a protected archive reported "2 couldn't be opened" and lost both reasons.
/// This is the thing that keeps them.
///
/// A value type with no view in it, because every decision here is a rule rather than a
/// layout: whether a notice appears at all, whether it names a publication or a count,
/// whether a set the reader has already dismissed comes back, and when an entry leaves. The
/// six-second toast it replaces needed none of those, which is why it had no test.
///
/// Android's `SkippedPublications` is the same type, asserted case for case.
public struct SkippedPublications: Sendable, Equatable {
    /// One publication and the reason `publication-formats` gives for refusing it.
    ///
    /// The name is the file's own last path component, which is all a publication that
    /// could not be indexed has — there is no metadata to read a title out of, because
    /// reading it is the thing that failed. It is still the name the reader sees in their
    /// own file browser, which is what makes it actionable.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let name: String
        /// Verbatim from the scanner. Deliberately not re-worded here: a second sentence
        /// for the same condition is a second thing to keep true.
        public let reason: String

        public var id: String { name }

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    /// What the library has to say about this, if anything.
    ///
    /// Four cases and not a `Bool` plus a count, because the four are genuinely different
    /// sentences and the delta spec gives each of them its own scenario. A view that
    /// switched on `entries.count` alone could not tell ``reachable`` from ``several``.
    public enum Notice: Sendable, Equatable {
        /// Nothing failed, or everything that had failed now opens.
        case nothing
        /// Exactly one, named, with its reason stated where the notice is.
        case one(name: String, reason: String)
        /// More than one. The count is here and the reasons are in the list.
        case several(count: Int)
        /// The reader dismissed it, and the list is still reachable.
        ///
        /// Not ``nothing``: the entries are still there and the way to them has to be too,
        /// "so a reader who dismissed it in the middle of something can come back to it".
        case reachable
    }

    /// What could not be opened, in the order the walk met it.
    public private(set) var entries: [Entry] = []

    /// The names the reader has already been shown and dismissed.
    ///
    /// Names rather than a single flag, which is what makes the *unless the set changes*
    /// half of the spec work: a scan that meets one new failure among four old ones has
    /// something to say, and a scan that meets the same four does not.
    private var acknowledged: Set<String> = []

    public init() {}

    public var notice: Notice {
        guard !entries.isEmpty else { return .nothing }
        guard entries.contains(where: { !acknowledged.contains($0.name) }) else { return .reachable }
        if entries.count == 1, let only = entries.first {
            return .one(name: only.name, reason: only.reason)
        }
        return .several(count: entries.count)
    }

    /// What a finished scan makes of this, replacing what the one before it made.
    ///
    /// Replacing rather than accumulating, and that single choice is what delivers three of
    /// the delta spec's scenarios at once:
    ///
    /// - *A publication that later opens* leaves without being dismissed, because a walk
    ///   that opened it does not report it, and a walk is the only thing that writes here.
    /// - A file the reader **deleted** leaves the same way. Nothing else would remove it,
    ///   and a list that keeps naming files that are gone is the graveyard the notice
    ///   exists to avoid becoming.
    /// - *The count is not shown again for the same publications* falls out of keeping the
    ///   acknowledgements that still have an entry, and dropping the ones that do not — so
    ///   a publication that is fixed and then breaks again is news a second time.
    ///
    /// - Parameter met: every refusal of one complete scan, in the order it met them. A
    ///   caller accumulates these across the several places one scan walks and settles
    ///   once, so a reader watching a two-folder scan does not see the first folder's
    ///   notice replaced halfway.
    public func settling(_ met: [Entry]) -> Self {
        var settled = self
        // The same file can be met twice — a remembered publication that also lives inside
        // a picked folder is walked both ways. First wins, so the order is the walk's.
        var seen: Set<String> = []
        settled.entries = met.filter { seen.insert($0.name).inserted }
        settled.acknowledged = settled.acknowledged.intersection(settled.entries.map(\.name))
        return settled
    }

    /// The reader put it away. The list stays.
    public func dismissing() -> Self {
        var dismissed = self
        dismissed.acknowledged = Set(entries.map(\.name))
        return dismissed
    }
}
