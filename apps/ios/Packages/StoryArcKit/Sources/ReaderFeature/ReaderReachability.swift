internal import Foundation
internal import Formats
internal import StoryArcCore

extension ReaderModel {
    /// One page's bytes, or nil when they could not be read.
    ///
    /// `network-share`'s *Network changes*, second clause: a page read in an open reader is
    /// where the app finds that the new path cannot reach the share, so it is where the
    /// library is told. Only an error that says the source is gone is reported. A damaged
    /// page or a refusal is not, and a publication with no source has nothing to report.
    nonisolated static func pageData(
        of page: PageEntry,
        in archive: any ComicArchiveReading,
        sourceID: UUID?
    ) async -> Data? {
        do {
            return try await archive.data(for: page)
        } catch {
            if let sourceID, (error as? any SourceReachabilityError)?.meansUnreachable == true {
                SourceReachabilityEvents.reportUnreachable(sourceID)
            }
            return nil
        }
    }
}
