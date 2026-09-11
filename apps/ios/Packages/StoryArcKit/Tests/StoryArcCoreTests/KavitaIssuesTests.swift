import Foundation
import Testing

@testable import StoryArcCore

/// The issues of a series the server matched, joined on this device.
///
/// `kavita-server`: a search of a Kavita source lists "the issues of every matched series
/// … joined on the device from the publications that source has already contributed to the
/// library". These are the cases the join has to get right, in the order Android's
/// `KavitaIssuesTest` asserts them.
struct KavitaIssuesTests {
    private let source = UUID()

    private func issue(_ series: String, _ chapterId: Int, title: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: PublicationIdentity.ServerIdentifier(
                    sourceID: source,
                    remoteID: "chapter:\(chapterId)"
                )
            ),
            format: .cbz,
            displayTitle: title ?? "\(series) #\(chapterId)",
            series: series,
            origin: .authoritative,
            sourceID: source
        )
    }

    private let greenLantern = KavitaHit(kind: .series, title: "Green Lantern (2005)", seriesId: 7)

    @Test("A matched series lists the issues the library holds")
    func issuesOfAMatchedSeries() {
        let joined = KavitaIssues.joined(
            [greenLantern],
            [issue("Green Lantern (2005)", 11), issue("Green Lantern (2005)", 12)]
        )
        let chapters = joined.filter { $0.kind == .chapter }
        #expect(chapters.map(\.title) == ["Green Lantern (2005) #11", "Green Lantern (2005) #12"])
        #expect(chapters.map(\.chapterId) == [11, 12])
    }

    @Test("The series the server matched is kept")
    func theSeriesIsKept() {
        let joined = KavitaIssues.joined([greenLantern], [issue("Green Lantern (2005)", 11)])
        #expect(joined.filter { $0.kind == .series } == [greenLantern])
    }

    @Test("A joined issue opens its series")
    func aJoinedIssueOpens() {
        let joined = KavitaIssues.joined([greenLantern], [issue("Green Lantern (2005)", 11)])
        let chapter = joined.first { $0.kind == .chapter }
        #expect(chapter?.seriesId == 7)
        #expect(chapter?.isOpenable == true)
        // Nothing on this device holds the file: the row leads to the server's series.
        #expect(chapter?.downloadId == nil)
    }

    @Test("A chapter the server already sent is not drawn twice")
    func theServersOwnChapterWins() {
        // The two producers name one chapter differently — the server answers with its own
        // display name, the library with the title `KavitaNaming` wrote — so the hit ids
        // differ and only kind, series and chapter tell them apart. A keyed list draws one
        // of two rows with one key.
        let fromServer = KavitaHit(kind: .chapter, title: "Rebirth", seriesId: 7, chapterId: 11)
        let joined = KavitaIssues.joined(
            [greenLantern, fromServer],
            [issue("Green Lantern (2005)", 11), issue("Green Lantern (2005)", 12)]
        )
        #expect(joined.filter { $0.kind == .chapter }.map(\.chapterId) == [11, 12])
        #expect(joined.first { $0.chapterId == 11 }?.title == "Rebirth")
        #expect(Set(joined.map(\.id)).count == joined.count)
    }

    @Test("A publication of another series contributes nothing")
    func anotherSeriesBringsNothing() {
        let joined = KavitaIssues.joined([greenLantern], [issue("Green Arrow (2001)", 11)])
        #expect(joined.filter { $0.kind == .chapter }.isEmpty)
    }

    @Test("A publication with no chapter of its own contributes nothing")
    func noChapterNoRow() {
        // A row from a folder or from a catalogue carries no Kavita chapter, so there is
        // nothing to open and nothing to key a row on.
        let local = Publication(
            identity: PublicationIdentity(normalizedPath: "/books/green-lantern.cbz"),
            format: .cbz,
            displayTitle: "Green Lantern (2005) #11",
            series: "Green Lantern (2005)",
            origin: .embedded
        )
        #expect(KavitaIssues.joined([greenLantern], [local]) == [greenLantern])
    }

    @Test("A person and a subject bring no issues")
    func namesBringNoIssues() {
        let person = KavitaHit(kind: .person, title: "Green Lantern (2005)")
        #expect(KavitaIssues.joined([person], [issue("Green Lantern (2005)", 11)]) == [person])
    }

    @Test("Nothing matched means nothing joined")
    func nothingMatched() {
        #expect(KavitaIssues.joined([], [issue("Green Lantern (2005)", 11)]).isEmpty)
    }
}
