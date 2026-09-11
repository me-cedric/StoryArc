import Foundation
import Testing

@testable import LibraryFeature

/// Which one line the shelf's notice strip draws.
///
/// `sources`' *Refresh visibility* states one refresh once, so the ranking is the
/// requirement: an incomplete shelf outranks a cached shelf, a cached shelf already says
/// "Checking for changes", a pulled refresh is spoken for by the pull indicator, and the
/// moment the sources last answered is the quietest thing left.
///
/// The pulled case is the one worth reading twice. A pull draws SwiftUI's own spinner at the
/// head of the shelf; a line at the foot saying the same thing is the app answering a
/// question the finger already answered.
///
/// Android's `SourceRefreshTest` asserts the same nine cases.
@Suite("Source refresh notices")
struct SourceRefreshTests {

    private let cachedAt = Date(timeIntervalSince1970: 1_000)
    private let checkedAt = Date(timeIntervalSince1970: 2_000)

    private func notice(
        refreshing: SourceRefreshOrigin? = nil,
        waiting: Int = 0,
        cached: Date? = nil,
        checked: Date? = nil
    ) -> LibraryNotice {
        LibraryNotice.of(
            refreshing: refreshing, waiting: waiting, cachedAt: cached, checkedAt: checked
        )
    }

    @Test("A shelf still missing a library says so before anything else")
    func incompleteShelfOutranksEverything() {
        #expect(
            notice(refreshing: .automatic, waiting: 2, cached: cachedAt, checked: checkedAt)
                == .stillBeingRead(2)
        )
    }

    @Test("A cached shelf outranks a refresh, because its own line already says checking")
    func cachedOutranksRefreshing() {
        #expect(
            notice(refreshing: .automatic, cached: cachedAt, checked: checkedAt)
                == .cached(cachedAt)
        )
    }

    @Test("A refresh nobody asked for is stated")
    func anAutomaticRefreshIsStated() {
        #expect(notice(refreshing: .automatic, checked: checkedAt) == .refreshing)
    }

    @Test("A pulled refresh draws no line, because the pull indicator is already drawn")
    func aPulledRefreshDrawsNoLine() {
        #expect(notice(refreshing: .pulled, checked: checkedAt) == .checked(checkedAt))
    }

    @Test("A pulled refresh on a shelf that never answered draws nothing at all")
    func aPulledRefreshOnAFreshShelfIsSilent() {
        #expect(notice(refreshing: .pulled) == LibraryNotice.none)
    }

    @Test("When nothing is running the strip says when the sources last answered")
    func checkedIsTheQuietestLine() {
        #expect(notice(checked: checkedAt) == .checked(checkedAt))
    }

    @Test("A library whose sources have never answered draws no indicator")
    func nothingToSay() {
        #expect(notice() == LibraryNotice.none)
    }

    @Test("A cached shelf with no refresh running still says it is cached")
    func cachedWithoutARefresh() {
        #expect(notice(cached: cachedAt) == .cached(cachedAt))
    }

    @Test("No source waiting is not the same as a source waiting")
    func zeroWaitingIsNotWaiting() {
        // The guard that keeps `waiting == 0` out of the first branch. Without it every
        // shelf would read "0 libraries are still being read".
        #expect(notice(waiting: 0) == LibraryNotice.none)
        #expect(notice(waiting: 1) == .stillBeingRead(1))
    }
}
