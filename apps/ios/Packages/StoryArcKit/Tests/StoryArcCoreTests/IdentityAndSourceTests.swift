import Foundation
import Testing

@testable import StoryArcCore

@Suite("Publication identity resolves the same book from different places")
struct PublicationIdentityTests {
    private let sourceID = UUID()

    @Test("A matching content digest resolves two records to the same publication")
    func digestMatch() {
        let fromFolder = PublicationIdentity(contentDigest: "d1", normalizedPath: "/a/b.cbz")
        let fromShare = PublicationIdentity(contentDigest: "d1", normalizedPath: "//nas/x.cbz")

        #expect(fromFolder.matches(fromShare))
    }

    @Test("A file that later gains a server id still matches its digest record")
    func digestSurvivesServerAdoption() {
        let local = PublicationIdentity(contentDigest: "d1")
        let server = PublicationIdentity(
            serverIdentifier: .init(sourceID: sourceID, remoteID: "42"),
            contentDigest: "d1"
        )

        #expect(local.matches(server))
    }

    @Test("The same remote id on two different servers is not the same publication")
    func serverIDsAreScopedToTheirSource() {
        let onKavitaOne = PublicationIdentity(serverIdentifier: .init(sourceID: UUID(), remoteID: "42"))
        let onKavitaTwo = PublicationIdentity(serverIdentifier: .init(sourceID: UUID(), remoteID: "42"))

        #expect(!onKavitaOne.matches(onKavitaTwo))
    }

    @Test("Unrelated publications do not match")
    func noMatch() {
        #expect(!PublicationIdentity(contentDigest: "d1").matches(PublicationIdentity(contentDigest: "d2")))
    }

    @Test("An identity with nothing recorded is empty and matches nothing")
    func emptyIdentity() {
        let empty = PublicationIdentity()

        #expect(empty.isEmpty)
        #expect(!empty.matches(PublicationIdentity(contentDigest: "d1")))
    }
}

@Suite("Source state and reconnection")
struct SourceStateTests {
    @Test("Only an unauthorized source asks the user to do something")
    func onlyUnauthorizedNeedsAction() {
        #expect(!SourceConnectionState.connected.needsUserAction)
        #expect(!SourceConnectionState.connecting.needsUserAction)
        #expect(!SourceConnectionState.unreachable(since: .now).needsUserAction)
        #expect(SourceConnectionState.unauthorized(reason: "401").needsUserAction)
    }

    @Test("Only a connected source can fetch content it has not downloaded")
    func onlyConnectedCanFetch() {
        #expect(SourceConnectionState.connected.canFetch)
        #expect(!SourceConnectionState.unreachable(since: .now).canFetch)
    }

    @Test("Backoff starts at five seconds, doubles, and caps at five minutes")
    func backoffCurve() {
        #expect(ReconnectBackoff.delay(forAttempt: 1) == .seconds(5))
        #expect(ReconnectBackoff.delay(forAttempt: 2) == .seconds(10))
        #expect(ReconnectBackoff.delay(forAttempt: 4) == .seconds(40))
        #expect(ReconnectBackoff.delay(forAttempt: 20) == .seconds(300))
    }
}

@Suite("Reading preference inference")
struct ReadingPreferenceTests {
    @Test("Japanese with no declared direction opens right to left")
    func japaneseDefaultsRTL() {
        #expect(ReadingDirection.inferred(declared: nil, languageCode: "ja") == .rightToLeft)
        #expect(ReadingDirection.inferred(declared: nil, languageCode: "ja-JP") == .rightToLeft)
    }

    @Test("A declared direction always wins over the language guess")
    func declaredWins() {
        #expect(ReadingDirection.inferred(declared: .leftToRight, languageCode: "ja") == .leftToRight)
    }

    @Test("An unknown language defaults to left to right")
    func unknownDefaultsLTR() {
        #expect(ReadingDirection.inferred(declared: nil, languageCode: nil) == .leftToRight)
    }

    @Test("Reduce Motion downgrades the animated transitions to a cross-dissolve")
    func reduceMotionDowngrade() {
        #expect(PageTransition.pageCurl.honoring(reduceMotion: true) == .fade)
        #expect(PageTransition.slide.honoring(reduceMotion: true) == .fade)
        #expect(PageTransition.verticalScroll.honoring(reduceMotion: true) == .verticalScroll)
        #expect(PageTransition.pageCurl.honoring(reduceMotion: false) == .pageCurl)
    }
}
