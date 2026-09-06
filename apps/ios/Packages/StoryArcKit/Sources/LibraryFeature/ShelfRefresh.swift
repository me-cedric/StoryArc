internal import Foundation

internal import StoryArcCore

/// What one pull re-fetches: the sources the shelf is showing, and no others.
///
/// `sources`' *Refreshing a source* asks a pull to "re-fetch the catalogue in the background"
/// and to update the view "incrementally rather than clearing it". It does not ask a pull on
/// one shelf to re-fetch the whole library, and both platforms did one of the two wrong
/// things: Android's pull walked the folders and asked no server at all, so a reader looking
/// at a server's shelf got nothing new; iOS asked every server *and* walked every folder on
/// every pull, so a reader on a metered link paid for the whole library because they pulled
/// one shelf.
///
/// **A folder walk is local disk and costs no data**, so it runs whenever the shelf could be
/// showing a folder's publications — including a library with no folder source at all, because
/// the managed import folder belongs to no source and is walked on every scan. **The network
/// is asked only when the shelf is showing something reached over one.**
///
/// Pure, and its own type, for the reason ``SourceProbe`` is: the decision is what a test can
/// reach, and a decision written inside a view modifier is a decision nothing can assert.
/// Android's `ShelfRefresh` holds the same table.
struct ShelfRefresh: Equatable {
    /// Whether the folders are walked again.
    let walksFolders: Bool
    /// Whether the sources that are reached over a network are asked again.
    let asksNetwork: Bool

    /// What a pull on this shelf should re-fetch.
    ///
    /// A scope naming a source that has gone is every source, which is
    /// ``LibraryScope/resolved(in:)``'s own answer: a stored scope pointing at a source
    /// removed last session must not turn a pull into nothing at all.
    static func of(_ scope: LibraryScope, in registry: SourceRegistry) -> ShelfRefresh {
        guard let id = scope.resolved(in: registry).sourceID, let one = registry[id] else {
            return ShelfRefresh(
                walksFolders: true,
                asksNetwork: registry.sources.contains { SourceProbe.isRemote($0.kind) }
            )
        }
        let isRemote = SourceProbe.isRemote(one.kind)
        return ShelfRefresh(walksFolders: !isRemote, asksNetwork: isRemote)
    }
}
