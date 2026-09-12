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
/// `node scripts/opds-server.mjs <corpus> --port 4444` and `--port 4445`; nothing listens on
/// 4999, so *Cellar Catalogue* is a refused connection rather than a name that does not
/// resolve — which are two different sentences, and only the first is *Not answering*.
enum MockCatalogues {

    /// What the reachable catalogues answer on, as a simulator sees the Mac.
    static let firstPort = 4444
    static let secondPort = 4445

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
