public import CoreGraphics
public import Foundation

internal import Catalogue
internal import Formats
internal import Persistence
public import StoryArcCore

/// The last rung of the cover ladder: ask an open catalogue, only when the reader said it may.
///
/// Task 6.1 of `cover-for-every-publication`. Three trust rules hold here and in
/// ``CoverLookupClient``, and each is asserted by a test: the setting is read at the moment
/// of use and nothing is read or asked while it is off, the request carries one identifier
/// and nothing else, and the client reaches only the hosts the setting names and reads at
/// most 8 MB of an answer. Android's `CoverLookupRung` is its twin.
struct CoverLookupRung: Sendable {
    let isEnabled: @Sendable () -> Bool
    let client: CoverLookupClient
    let identify: @Sendable (Publication, URL) async -> CoverIdentifier?

    /// The one rung of the process, so every caller shares one client and one cache file.
    ///
    /// A variable only so a test can put a stub transport behind it and restore it after.
    nonisolated(unsafe) static var live: CoverLookupRung = {
        let isOn: @Sendable () -> Bool = { SettingsStore().settings().lookUpMissingCovers }
        return CoverLookupRung(
            isEnabled: isOn,
            client: CoverLookupClient(isEnabled: isOn),
            identify: { await CoverIdentifierReader.identifier(for: $0, at: $1) }
        )
    }()

    /// The picture a catalogue holds for this publication, or nil.
    ///
    /// The gate comes before the identifier is read, so a reader with the lookup off costs
    /// the file no extra read at all. The publication's id keys the cache; it never travels.
    func picture(for publication: Publication, at url: URL) async -> Data? {
        guard isEnabled(), let identifier = await identify(publication, url) else { return nil }
        return await client.coverImage(for: publication.id, identifier: identifier)
    }

    /// The cover from the rungs that need the file, then the lookup.
    func cover(
        for publication: Publication, at url: URL, maxPixelSize: Int, ladder: CoverLadder
    ) async -> CGImage? {
        if let image = await ladder.cover(for: publication, at: url, maxPixelSize: maxPixelSize) {
            return image
        }
        guard let picture = await picture(for: publication, at: url) else { return nil }
        return try? PageDecoder.decode(picture, maxPixelSize: maxPixelSize)
    }
}
