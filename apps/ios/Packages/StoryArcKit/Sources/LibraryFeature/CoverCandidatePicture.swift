import CoreGraphics
import Foundation

internal import Catalogue
internal import Formats

/// What the candidate sheet decides before it draws, lifted out of the view so a test can
/// reach it.
///
/// Task 6.3 of `cover-for-every-publication`. Android's `candidateKey` and `CandidatePicture`
/// are its twins.
enum CoverCandidatePicture {

    /// One row of the sheet, and the identity SwiftUI keeps it under.
    struct Row: Identifiable {
        let id: String
        let candidate: CoverCandidate
    }

    /// Every candidate as a row of its own.
    ///
    /// Provider, address and position, because two catalogues can answer one title with the
    /// same picture and one catalogue can repeat itself, and a list that meets an identity
    /// twice draws one row for two. The position makes it unique by construction, which no
    /// field of the answer can.
    static func rows(_ candidates: [CoverCandidate]) -> [Row] {
        candidates.enumerated().map { index, candidate in
            Row(
                id: "\(candidate.provider.rawValue)|\(candidate.imageURL.absoluteString)|\(index)",
                candidate: candidate
            )
        }
    }

    /// The candidate's picture, decoded, or nil.
    ///
    /// Fetched through ``CoverLookupClient/image(at:)``, the one path that checks the setting
    /// and the host. `AsyncImage` loads on the shared session and checks neither, so a picture
    /// from an address the setting does not name would have been requested by the sheet.
    static func picture(
        for candidate: CoverCandidate, via client: CoverLookupClient, maxPixelSize: Int = 264
    ) async -> CGImage? {
        guard let data = await client.image(at: candidate.imageURL) else { return nil }
        return try? PageDecoder.decode(data, maxPixelSize: maxPixelSize)
    }
}
