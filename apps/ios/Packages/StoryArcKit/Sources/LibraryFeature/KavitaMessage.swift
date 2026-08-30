internal import Foundation

internal import Kavita

/// Why a Kavita server did not answer, in the reader's words rather than the enum's.
///
/// **`kavita-server`'s revoked-key scenario asks for "an explanation and an action".** The
/// marking was right on both platforms — a refused key puts the source in `unauthorized`,
/// which `SourceDiagnosis` answers with the `reconnect` action, and that re-opens the sheet
/// the server was added through with everything but the secret filled in. What was missing
/// here was the sentence: the browser printed `String(describing: error)`, so a reader whose
/// key had been revoked was shown the word `keyRejected` and left to work out that their
/// server was fine and their key was not.
///
/// The explanation names the action rather than describing the failure twice, because a
/// reader who has just been told what is wrong wants to know where to fix it. Android's
/// `KavitaMessage` says the same four things.
enum KavitaMessage {
    static func of(_ error: any Error, source: String) -> String {
        guard let kavita = error as? KavitaError else {
            return String(
                format: String(localized: "source.offline.body %@", bundle: .module, locale: .storyArc),
                source
            )
        }
        switch kavita {
        // The key the keychain still holds is one the server no longer accepts. Not the
        // same as a missing key, and not the same as a server that is down.
        case .keyRejected:
            return String(
                format: String(
                    localized: "source.unauthorized.refused.body %@", bundle: .module, locale: .storyArc
                ),
                source
            )
        case let .serverTooOld(found, required):
            return String(
                format: String(localized: "kavita.error.tooOld", bundle: .module, locale: .storyArc),
                found.description,
                required.description
            )
        case .badAddress, .unexpectedResponse:
            return String(localized: "kavita.error.notKavita", bundle: .module, locale: .storyArc)
        // Any other status is the server being unwell rather than the reader being wrong,
        // and `sources` makes that a grey state with an offer to try again.
        case .http:
            return String(
                format: String(localized: "source.offline.body %@", bundle: .module, locale: .storyArc),
                source
            )
        }
    }
}
