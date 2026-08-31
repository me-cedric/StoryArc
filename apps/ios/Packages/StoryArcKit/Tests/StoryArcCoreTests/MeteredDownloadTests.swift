import Testing

@testable import StoryArcCore

/// `offline-downloads`' *Overriding once* and *Wi-Fi only*, asserted case for case.
/// Android's `MeteredDownloadTest` asserts the same cases.
///
/// The clause that matters is "for that item only". Everything here is about keeping the
/// grant to one publication: a reader who agreed to spend data on one comic has not agreed
/// to release the queue behind it, and a rule that could not tell those apart would turn a
/// single confirmation into a standing permission.
@Suite("An override is granted per publication, not to the queue")
struct MeteredDownloadTests {
    @Test("On a metered link an ungranted download is confirmed first")
    func meteredAsks() {
        #expect(MeteredDownload.needsConfirmation(isMetered: true, isOverridden: false))
    }

    @Test("Off a metered link nothing is asked")
    func unmeteredDoesNotAsk() {
        // The tap is the whole interaction it has always been.
        #expect(!MeteredDownload.needsConfirmation(isMetered: false, isOverridden: false))
        #expect(!MeteredDownload.needsConfirmation(isMetered: false, isOverridden: true))
    }

    @Test("A grant already given is not asked for twice")
    func grantedDoesNotAskAgain() {
        // Which is what makes Download work the second time a reader presses it.
        #expect(!MeteredDownload.needsConfirmation(isMetered: true, isOverridden: true))
    }

    @Test("Wi-Fi-only holds a metered download that carries no grant")
    func wifiOnlyHolds() {
        #expect(!MeteredDownload.mayStart(wifiOnly: true, isMetered: true, isOverridden: false))
    }

    @Test("The granted publication starts while the rest of the queue waits")
    func theGrantIsPerItem() {
        // The whole of "proceeds for that item only": the same settings, the same
        // connection, and two different answers depending only on which download is asked
        // about.
        #expect(MeteredDownload.mayStart(wifiOnly: true, isMetered: true, isOverridden: true))
        #expect(!MeteredDownload.mayStart(wifiOnly: true, isMetered: true, isOverridden: false))
    }

    @Test("Wi-Fi-only on Wi-Fi holds nothing")
    func wifiOnlyOnWifiIsNoBar() {
        #expect(MeteredDownload.mayStart(wifiOnly: true, isMetered: false, isOverridden: false))
    }

    @Test("With the setting off a metered download runs unasked-for permission")
    func settingOffLetsItRun() {
        // The reader was still *confirmed* — that is `needsConfirmation`'s job, and it does
        // not consult the setting — but nothing holds the queue afterwards.
        #expect(MeteredDownload.mayStart(wifiOnly: false, isMetered: true, isOverridden: false))
    }
}
