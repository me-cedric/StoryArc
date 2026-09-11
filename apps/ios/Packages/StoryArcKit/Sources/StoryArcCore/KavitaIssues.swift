/// The issues of a series a Kavita server matched, joined on this device.
///
/// **Kavita cannot answer this, and its own source says why.** A chapter is matched on
/// `EF.Functions.Like(c.TitleName, ...)`, on `c.ISBN` and on `c.Range` —
/// `API/Data/Repositories/SeriesRepository.cs` at tag v0.8.7. A chapter row carries no
/// series name, so "lantern" matches no chapter of "Green Lantern (2005)" and a reader who
/// searched for their series got fifteen series and no files. The response's `Files` group
/// looks like the answer and is not: the server fills it for an administrator only, and the
/// file it names carries neither a series nor a chapter, so it cannot be opened.
///
/// So the join is here, over publications the library already holds. `KavitaContributor`
/// makes one ``Publication`` per chapter, each carrying the series name the server gave it,
/// the chapter's own title and the chapter's remote id. The server's series hit carries the
/// numeric series id the library rows lack. Together they are the issue rows.
///
/// Pure, for the reason ``KavitaFind`` gives: which rows a search answers with is a
/// decision, not a screen. A new file rather than a member of ``KavitaFind``, because
/// `KavitaFind.swift` is three lines under its cap. Android's `KavitaIssues` is the twin.
public enum KavitaIssues {
    /// What a chapter's remote id is prefixed with. See `KavitaContributor.publication`.
    private static let chapterPrefix = "chapter:"

    /// The server's hits, and the issues of every series among them that the library holds.
    ///
    /// The series name is matched exactly, because `KavitaContributor` writes a
    /// publication's series from the same `KavitaSeries.name` the server answers a series
    /// hit with. A looser match would file one series' issues under another's name.
    ///
    /// - Parameters:
    ///   - hits: what the server matched.
    ///   - publications: what the library holds for the searched source, and nothing else:
    ///     a chapter id is unique to one server, so rows from another would join wrongly.
    public static func joined(_ hits: [KavitaHit], _ publications: [Publication]) -> [KavitaHit] {
        let series = hits.filter { $0.kind == .series }
        guard !series.isEmpty else { return hits }

        // Identity is the chapter, not the row's words. The server names a chapter with its
        // own display name and the library with the title `KavitaNaming` wrote, so two rows
        // for one chapter carry two ``KavitaHit/id``s — and a keyed list draws one of them.
        var seen = Set(hits.map(chapterKey))
        var joined: [KavitaHit] = []
        for matched in series {
            for publication in publications where publication.series == matched.title {
                guard let chapter = chapterId(of: publication) else { continue }
                let hit = KavitaHit(
                    kind: .chapter,
                    title: publication.displayTitle,
                    seriesId: matched.seriesId,
                    chapterId: chapter
                )
                guard seen.insert(chapterKey(hit)).inserted else { continue }
                joined.append(hit)
            }
        }
        return hits + joined
    }

    /// Which chapter of which series a row is, ignoring what the row is called.
    private static func chapterKey(_ hit: KavitaHit) -> String {
        "\(hit.kind):\(hit.seriesId):\(hit.chapterId)"
    }

    /// The Kavita chapter this publication is, or `nil` when it is not one.
    ///
    /// A row from a folder, a catalogue or a share carries no server chapter, so there is
    /// nothing to open and nothing to key a row on.
    private static func chapterId(of publication: Publication) -> Int? {
        guard let remote = publication.identity.serverIdentifier?.remoteID,
              remote.hasPrefix(chapterPrefix)
        else { return nil }
        return Int(remote.dropFirst(chapterPrefix.count))
    }
}
