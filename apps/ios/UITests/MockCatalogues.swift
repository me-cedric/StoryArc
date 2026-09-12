import Foundation
import XCTest

/// The three mock catalogues a source walk runs against.
///
/// **Why a fixture rather than the device's own sources.** `source-lifecycle` owes frames of
/// states only a registered source reaches — the detail screen with its five fields, the
/// removal confirmation with a real title count, an unreachable server beside a reachable one,
/// and one title held by two sources. A simulator's registry is whoever last used it, so a
/// walk that reads it photographs a different screen each week, and `testCaptureSettingsSourceDetail`
/// skipped outright on a device with no catalogue.
///
/// `sweepLaunch(sources:)` injects a registry as a launch argument, so the walk decides what
/// it is looking at. The same three sources, with the same names and the same identifiers, are
/// what `scripts/seed-android-sources.mjs` and `scripts/seed-simulator-sources.mjs` write — so
/// an Android frame and an iOS frame of one state name the same libraries.
///
/// **Two of them answer and one does not.** The mock catalogues are
/// `node scripts/opds-server.mjs <corpus> --port 4444` and `--port 4447`; nothing listens on
/// 4999, so *Cellar Catalogue* is a refused connection rather than a name that does not
/// resolve — which are two different sentences, and only the first is *Not answering*.
enum MockCatalogues {

    /// What the reachable catalogues answer on, as a simulator sees the Mac.
    static let firstPort = 4444
    /// 4447, and the two ports it skips are the reason. `scripts/smb-server.sh` binds 4445,
    /// and its `--encrypted` twin binds 4446. Both SMB suites decide whether to run by
    /// opening a socket on their port, so a mock catalogue on either one answers that socket
    /// and the SMB cases run against a catalogue: six failed that way on 2026-09-12, with
    /// "Failed to connect" about a server that was listening. Every fixture port this
    /// repository uses is listed in `AGENTS.md`.
    static let secondPort = 4447

    /// A port nothing listens on.
    static let deadPort = 4999

    static let attic = "Attic Catalogue"
    static let loft = "Loft Catalogue"
    static let cellar = "Cellar Catalogue"

    /// The registry `sweepLaunch(sources:)` takes, as `StoredRegistry` JSON.
    ///
    /// Fixed identifiers, so a download record a walk writes can name a source that exists.
    /// `lastSuccessfulSync` is null on every one: connection state is never persisted, and a
    /// *Last synchronised* the app never earned would be a claim about a past that did not
    /// happen.
    static var registry: String {
        """
        {
          "sources": [
            {
              "id": "11111111-1111-4111-8111-111111111111",
              "displayName": "\(attic)",
              "kind": "opdsCatalog",
              "lastSuccessfulSync": null,
              "credentialReference": null,
              "locator": "http://127.0.0.1:\(firstPort)/opds/all"
            },
            {
              "id": "22222222-2222-4222-8222-222222222222",
              "displayName": "\(loft)",
              "kind": "opdsCatalog",
              "lastSuccessfulSync": null,
              "credentialReference": null,
              "locator": "http://127.0.0.1:\(secondPort)/opds/all"
            },
            {
              "id": "33333333-3333-4333-8333-333333333333",
              "displayName": "\(cellar)",
              "kind": "opdsCatalog",
              "lastSuccessfulSync": null,
              "credentialReference": null,
              "locator": "http://127.0.0.1:\(deadPort)/opds/all"
            }
          ],
          "tombstones": []
        }
        """
    }

    /// A registry whose only source cannot be reached, which is the *library away* state.
    ///
    /// **Why one source and not three.** ``LibraryAway/everythingAway(in:)`` is true only when
    /// every configured source is unreachable, and the three-catalogue registry above has two
    /// that answer. A reader with one dead catalogue is the smallest honest way to reach the
    /// sentence `library-browsing` owes a picture of.
    ///
    /// **It needs a device with no books of its own.** The shelf falls through to
    /// ``LibraryAway`` only after "narrowed to nothing", and that branch is taken whenever the
    /// device holds any publication at all — so a seeded simulator shows the filter sentence
    /// instead. `SweepSourcesTests.testCaptureAwayNotice` carries the command that clears one.
    static var everythingAway: String {
        """
        {
          "sources": [
            {
              "id": "33333333-3333-4333-8333-333333333333",
              "displayName": "\(cellar)",
              "kind": "opdsCatalog",
              "lastSuccessfulSync": null,
              "credentialReference": null,
              "locator": "http://127.0.0.1:\(deadPort)/opds/all"
            }
          ],
          "tombstones": []
        }
        """
    }

    /// A Kavita server whose key is gone, which is the *refused credential* state.
    ///
    /// **Deterministic, and that is the point.** §4.2 sat open because the refusal it needed
    /// was a race: a mock served with a rotated key answers 401 on one launch and a connection
    /// failure on the next, and only the first offers *Reconnect*. This needs no server at
    /// all. `LibrarySourceHealth` ends with "neither page could be built, so the secret this
    /// source needs has gone" and returns `.unauthorized` — the same state a refusal reaches,
    /// reached by the one route that cannot flicker.
    ///
    /// A `credentialReference` naming a secret the keychain does not hold is how it is built:
    /// `KavitaPage(source:credentials:)` is nil without the key, and its own comment says that
    /// is what unauthorized means.
    static var refusedKavita: String {
        """
        {
          "sources": [
            {
              "id": "44444444-4444-4444-8444-444444444444",
              "displayName": "Attic Kavita",
              "kind": "kavitaServer",
              "lastSuccessfulSync": null,
              "credentialReference": "a-secret-this-keychain-does-not-hold",
              "locator": "http://127.0.0.1:5000"
            }
          ],
          "tombstones": []
        }
        """
    }
    /// Whether the mock catalogues are actually up, so a walk skips with a reason rather than
    /// photographing three unreachable sources and calling one of them reachable.
    ///
    /// Asked of the first port only. The second serves the same corpus from the same script,
    /// and a walk that needed both would be reporting the fixture's own health twice.
    static func areRunning() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(firstPort)/opds/all") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let answered = XCTestExpectation(description: "the mock catalogue answers")
        var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            answered.fulfill()
        }.resume()
        _ = XCTWaiter().wait(for: [answered], timeout: 5)
        return reachable
    }
}
