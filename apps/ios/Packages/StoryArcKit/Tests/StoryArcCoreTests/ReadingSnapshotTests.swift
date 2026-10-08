import Foundation
import Testing

@testable import StoryArcCore

/// The record a home-screen widget reads, asserted against the same table as Android's
/// `ReadingSnapshotTest`. Add a case here, add it there.
@Suite("Reading snapshot")
struct ReadingSnapshotTests {

    private func publication(_ title: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/" + title),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .inferred
        )
    }

    @Test("No publication, or one with a blank title, gives no snapshot")
    func nothingToShow() {
        #expect(ReadingSnapshot(publication: nil, fractionRead: 0.5) == nil)
        #expect(ReadingSnapshot(publication: publication("   "), fractionRead: 0.5) == nil)
    }

    @Test("The percent is rounded down, so only a finished book shows 100")
    func percentRoundsDown() throws {
        let bone = publication("Bone 1")
        #expect(try #require(ReadingSnapshot(publication: bone, fractionRead: 0.996)).percentRead == 99)
        #expect(try #require(ReadingSnapshot(publication: bone, fractionRead: 1)).percentRead == 100)
        #expect(try #require(ReadingSnapshot(publication: bone, fractionRead: nil)).percentRead == nil)
        #expect(try #require(ReadingSnapshot(publication: bone, fractionRead: -0.2)).percentRead == 0)
    }

    @Test("A snapshot survives its stored form")
    func roundTrip() throws {
        let snapshot = try #require(
            ReadingSnapshot(publication: publication("Bone 1", series: "Bone"), fractionRead: 0.42)
        )
        #expect(ReadingSnapshot.decoded(try snapshot.encoded()) == snapshot)
        #expect(snapshot.series == "Bone")
        #expect(snapshot.fractionRead == 0.42)
    }

    @Test("A record in another format, malformed, or with no title is not read")
    func refusedRecords() {
        func record(_ json: String) -> ReadingSnapshot? { ReadingSnapshot.decoded(Data(json.utf8)) }
        #expect(record(#"{"version":2,"publicationID":"a","title":"Bone 1"}"#) == nil)
        #expect(record(#"{"version":1,"publicationID":"a","title":"  "}"#) == nil)
        #expect(record(#"{"version":1,"publicationID":"","title":"Bone 1"}"#) == nil)
        #expect(record("not json") == nil)
        #expect(record(#"{"version":1,"publicationID":"a","title":"Bone 1","percentRead":140}"#)?.percentRead == 100)
    }

    /// Shared with Android's `ReadingSnapshotTest`: the same identifier names the same file.
    @Test("The cover file name is the FNV-1a hash of the identifier")
    func coverFileName() {
        #expect(ReadingSnapshot.coverFile(for: "path:/library/Bone 1") == "cover-8082a1c0582fd210.jpg")
        #expect(ReadingSnapshot.coverFile(for: "") == "cover-cbf29ce484222325.jpg")
    }

    @Test("A widget link opens the same book a quick action would")
    func linkRoundTrip() throws {
        let odd = Publication(
            identity: PublicationIdentity(normalizedPath: "/a b/c&d=e?.cbz"),
            format: .cbz,
            displayTitle: "Odd",
            origin: .inferred
        )
        let snapshot = try #require(ReadingSnapshot(publication: odd, fractionRead: 0.1))
        #expect(
            QuickActionRequest(widgetURL: ReadingSnapshot.link(to: snapshot)) == .continueReading(id: odd.id)
        )
        #expect(QuickActionRequest(widgetURL: ReadingSnapshot.link(to: nil)) == .library)
    }

    @Test("Any other link moves nothing")
    func foreignLinks() throws {
        #expect(QuickActionRequest(widgetURL: try #require(URL(string: "https://continue?publication=a"))) == nil)
        #expect(QuickActionRequest(widgetURL: try #require(URL(string: "storyarc://elsewhere"))) == nil)
        #expect(QuickActionRequest(widgetURL: try #require(URL(string: "storyarc://continue"))) == nil)
    }
}
