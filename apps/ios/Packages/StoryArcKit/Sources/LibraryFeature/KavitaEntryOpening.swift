internal import Foundation

internal import Formats
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// How one try to open a reading-list entry ended.
///
/// A failed open used to clear the row's spinner and say nothing, so the reader could not tell
/// a refusal from a wait. `kavita-server` asks that a failure state its reason instead.
enum KavitaEntryOpening: Sendable {
    case opened(Publication, URL)
    /// The server did not hand the file over: unreachable, refused or unwell.
    case notSent
    /// The file arrived, and it is not one StoryArc can read.
    case unreadable

    /// Fetches one entry's chapter and indexes it, the way the chapter list does.
    ///
    /// A reading-list entry used to open with neither an origin nor a recorded server
    /// identity: the reader could read here and the position never left the device, because
    /// nothing named which server or which chapter it belonged to.
    static func attempt(
        _ entry: KavitaReadingListItem,
        sourceId: String,
        store: KavitaProgressStore,
        from client: KavitaClient
    ) async -> Self {
        guard let fetched = try? await client.chapter(entry.chapterId) else { return .notSent }
        guard let file = kavitaCacheFile(
                  chapterId: entry.chapterId,
                  mediaType: fetched.mediaType,
                  named: entry.seriesName.map { "\($0) \(entry.chapterId)" }
              ),
              (try? fetched.bytes.write(to: file, options: .atomic)) != nil,
              var publication = try? await PublicationIndexer.index(
                  fileAt: file,
                  catalogueSeries: entry.seriesName
              )
        else { return .unreadable }

        let origin = KavitaOrigin(
            sourceId: sourceId,
            libraryId: entry.libraryId,
            seriesId: entry.seriesId,
            volumeId: entry.volumeId,
            chapterId: entry.chapterId,
            pages: entry.pagesTotal
        )
        publication.identity = publication.identity.recordingServer(origin.serverIdentifier)
        store.remember(origin, for: publication.id)
        return .opened(publication, file)
    }

    /// Why the open failed, in the reader's words, or nil when it opened.
    func reason(server: String) -> String? {
        switch self {
        case .opened: nil
        case .notSent:
            String(localized: "kavita.open.notSent \(server)", bundle: .module, locale: .storyArc)
        case .unreadable:
            String(localized: "kavita.open.unreadable \(server)", bundle: .module, locale: .storyArc)
        }
    }
}
