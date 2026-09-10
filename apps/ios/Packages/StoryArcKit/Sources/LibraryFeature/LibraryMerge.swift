import Foundation
import StoryArcCore

/// What a row becomes when the library meets the same publication again.
///
/// The old answer was "the same row, re-attributed": only the source changed. That is right
/// for a file, whose metadata is read out of the file and does not change unless the file
/// does. It is wrong for a server.
///
/// `sources` requires a refresh to "re-fetch the catalogue" and "update the view
/// incrementally", and ``MetadataOrigin/authoritative`` means the source owns the answer. A
/// row a server supplied must therefore take the server's newer answer — otherwise a title
/// corrected on the server, or by a bug fixed in this app, is stuck in the cache until the
/// reader clears it by hand.
///
/// **A downloaded file still wins over a server's description of it.** Only a row with
/// nothing on disk is re-described. Android's `LibraryMerge` is its twin.
enum LibraryMerge {

    /// The row to keep: `existing` re-attributed, or `found` where a source owns the answer.
    static func merged(
        existing: Publication,
        found: Publication,
        sourceID: UUID?,
        hasFile: Bool
    ) -> Publication {
        guard found.origin == .authoritative, !hasFile else {
            var kept = existing
            kept.sourceID = sourceID
            return kept
        }
        // The server's description, kept under the row's own identity so nothing stored
        // against it moves — a publication's key must not change.
        var replaced = found
        replaced.identity = existing.identity
        replaced.sourceID = sourceID
        return replaced
    }

    /// Whether a find replaces the row already on the shelf.
    ///
    /// ``SourcePrecedence`` answers *which of two sources wins*, strictly, which is right
    /// for that question and wrong for this one: a source re-read is not a different
    /// source, so it lost every comparison with itself and a refresh could never correct
    /// anything it had already written.
    static func replaces(_ found: UUID?, over existing: UUID?, in sources: [Source]) -> Bool {
        found == existing || SourcePrecedence.prefers(found, over: existing, in: sources)
    }
}

extension LibraryModel {
    /// Puts a publication in the library under the source it was reached through, and
    /// says whether it was new.
    ///
    /// Shared by the folder scan, by the imported copies and by ``readServers()``, which
    /// find publications three entirely different ways and have to agree about what one
    /// row means.
    @discardableResult
    func adopt(_ publication: Publication, from sourceID: UUID?) -> Bool {
        var attributed = publication
        attributed.sourceID = sourceID

        // A publication already present from another folder is not added twice.
        // Identity is what decides, not the path, so the same file reached two ways
        // is one row (ADR-0006).
        if let seen = publications.firstIndex(
            where: { $0.identity.matches(publication.identity) }
        ) {
            // Unless this find came through a source the reader put higher. `sources`: the
            // combined view "lists titles from higher sources first when two sources hold
            // the same publication" — so the registry's order decides which copy the row is,
            // not which scan happened to reach it first. ``SourcePrecedence`` is where that
            // comparison lives and where it is asserted.
            //
            // The unattributed case falls out of the same rule: the app's own Documents
            // folder is scanned before any source is restored, so a reader whose library
            // lives there had every publication found with no source at all — and a source
            // holding eleven books reported nought. Nil ranks last, so the source wins.
            // ``LibraryMerge`` rather than ``SourcePrecedence`` directly: a re-read is
            // not a different source, and a strict comparison meant a source lost against
            // itself, so a refresh could never correct a row it had written.
            guard LibraryMerge.replaces(
                attributed.sourceID,
                over: publications[seen].sourceID,
                in: registry.sources
            ) else { return false }

            publications[seen] = LibraryMerge.merged(
                existing: publications[seen],
                found: publication,
                sourceID: attributed.sourceID,
                hasFile: locations[publications[seen].id] != nil
            )
            // The file goes with the attribution. A row that says one source and opens the
            // other source's copy is the same bug wearing a different hat.
            if let path = publication.identity.normalizedPath {
                locations[publications[seen].id] = URL(fileURLWithPath: path)
            }
            return false
        }

        publications.append(attributed)
        if let path = publication.identity.normalizedPath {
            locations[publication.id] = URL(fileURLWithPath: path)
        }
        return true
    }
}
