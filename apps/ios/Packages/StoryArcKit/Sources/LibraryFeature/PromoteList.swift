internal import Foundation

internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Putting a reading list a reader made here onto a Kavita server.
///
/// `collections-and-reading-lists`: when a reader wants a local list on a server "the app
/// offers to copy it, and states which entries cannot be included because they do not exist
/// on that server". Copied, not moved — the local list is left exactly as it was, because it
/// is the only place the entries the server cannot hold still exist.
///
/// Nothing is uploaded. This app has no backend and pushes no files anywhere, so "the server
/// has it" means one thing only: the publication was opened from that server, and
/// ``KavitaProgressStore`` wrote down which chapter it was. That note is what the copy sends,
/// and its absence is why an entry is left behind.
extension LibraryModel {
    /// What copying this list onto this server would move, and what it would leave behind.
    ///
    /// Worked out before anything happens and shown to the reader, then used again to decide
    /// what is actually sent. One answer, so the screen cannot promise a different copy from
    /// the one that runs.
    func promotion(of list: ReadingList, to server: KavitaPage) -> ListPromotion {
        let kavita = KavitaProgressStore()
        return ListPromotion(entries: list.entries) { entry in
            kavita.origin(of: entry)?.sourceId == server.id
        }
    }

    /// Copies a local reading list onto a server, in the list's own order.
    ///
    /// Answers with what the reader can undo, or `nil` when nothing reached the server. The
    /// entries go one at a time rather than grouped by series: Kavita appends in the order it
    /// is asked, and grouping would rearrange a crossover into series order — which is the
    /// one thing a reading list exists to prevent.
    func promote(_ list: ReadingList, to server: KavitaPage) async -> BulkUndo? {
        let kavita = KavitaProgressStore()
        let plan = promotion(of: list, to: server)
        guard plan.isPossible else { return nil }

        let client = KavitaClient(address: server.address)
        guard let made = try? await client.createList(named: list.name) else { return nil }

        var copied: Set<String> = []
        for entry in plan.copying {
            guard let origin = kavita.origin(of: entry) else { continue }
            guard (try? await client.append(
                toList: made.id,
                seriesId: origin.seriesId,
                chapterIds: [origin.chapterId]
            )) != nil else { continue }
            copied.insert(entry)
        }

        // The server went away between the plan and the copy. Leaving an empty list behind
        // would put something on the server that nobody asked for and nobody can explain.
        guard !copied.isEmpty else {
            try? await client.deleteList(made.id)
            return nil
        }

        return BulkUndo(kind: .promoted(sourceID: server.id, listID: made.id), ids: copied)
    }

    /// Takes a copied list back off the server, within its ten seconds.
    ///
    /// The key is read here rather than held in the undo record: a record waiting out its
    /// window is view state, and view state is not where a secret belongs.
    func withdraw(_ listID: Int, from sourceID: String) async {
        let credentials = CredentialStore()
        guard let address = registry.sources
            .first(where: { $0.id.uuidString == sourceID })
            .flatMap({ KavitaPage(source: $0, credentials: credentials)?.address })
        else { return }
        try? await KavitaClient(address: address).deleteList(listID)
    }
}
