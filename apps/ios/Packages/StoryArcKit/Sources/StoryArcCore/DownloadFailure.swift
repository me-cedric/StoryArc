public import Foundation

/// Why a download stopped, as a code and its arguments rather than as a sentence.
///
/// **A stored sentence keeps the language it was written in.** `localization` 15.9: the queue
/// wrote `offline-downloads`' "plain-language reason" into the record at the moment of
/// failure, and that record outlives the moment. A reader who then switched the app to French
/// kept reading an English refusal on every failed row, for ever — the row is drawn from the
/// store, and the store held a finished sentence nothing could translate.
///
/// So the record holds what happened and the screen says it. ``DownloadFailureWords`` is the
/// saying, in `LibraryFeature`, where the strings are.
///
/// **A closed set, never free text.** The same rule ``Formats/PublicationIndexer/IndexError``
/// follows: a case the compiler checks cannot have a sentence written into it by accident, and
/// every case here has to have a word in four languages before it can be drawn at all.
///
/// Android's `DownloadFailure` carries the same cases under the same names, plus
/// one more: its queue words a locked file in its own sentence and
/// this one does not yet, so a case iOS can never store is left out rather than given a word
/// that is not true of it.
public enum DownloadFailure: Sendable, Equatable {
    /// A container StoryArc recognises and does not read, carrying the name so the sentence
    /// can say "7-Zip" rather than "could not open file".
    case unsupportedFormat(String)

    /// The bytes arrived and were not a publication this app can open.
    case unreadable

    /// The catalogue refused the sign-in it was given.
    case unauthorized

    /// The server answered with nothing at all.
    case empty

    /// An address this app will not follow — not a web address, or a step down to cleartext.
    case refusedAddress

    /// A redirect loop, or a redirect with no address to follow.
    case redirect

    /// A web page where a catalogue was expected, which is usually a sign-in page.
    case notAWebPage

    /// Something that is not a catalogue, carrying the content type when the server named one.
    case notAFeed(String?)

    /// A catalogue whose own bytes could not be parsed.
    case malformed

    /// The server refused, carrying the status it refused with.
    case http(Int)

    /// The host could not be found.
    case noHost

    /// The server did not answer in time.
    case timedOut

    /// This device has no connection at all.
    case offline

    /// The server could not be reached, for a reason none of the above names.
    case unreachable

    /// What an older build's stored sentence becomes when the record is read.
    ///
    /// `localization` 15.9 asks for exactly this: an existing install must not show an empty
    /// reason where it used to show an English one. The sentence itself is dropped rather than
    /// kept — it is in whichever language the app spoke when it was written, which is the
    /// defect — so the honest replacement is a reason that says only that the download failed.
    case unknown

    /// The record's own spelling: the code, and its argument after a newline when it has one.
    ///
    /// Newline-separated and code-first, the convention `OpdsCredential.stored` already uses
    /// in this repository. A colon would be ambiguous — a content type contains one.
    public var stored: String {
        switch self {
        case let .unsupportedFormat(format): "unsupportedFormat\n\(format)"
        case .unreadable: "unreadable"
        case .unauthorized: "unauthorized"
        case .empty: "empty"
        case .refusedAddress: "refusedAddress"
        case .redirect: "redirect"
        case .notAWebPage: "notAWebPage"
        case let .notAFeed(type): type.map { "notAFeed\n\($0)" } ?? "notAFeed"
        case .malformed: "malformed"
        case let .http(status): "http\n\(status)"
        case .noHost: "noHost"
        case .timedOut: "timedOut"
        case .offline: "offline"
        case .unreachable: "unreachable"
        case .unknown: "unknown"
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// Reads back what ``stored`` wrote, and reads anything else as ``unknown``.
    ///
    /// Anything else is a sentence an older build wrote, or a code a newer build knows and this
    /// one does not. Both are reasons this build cannot say, and neither is a reason to lose
    /// the download.
    ///
    /// One branch per case of a closed set, which is what makes the set closed: splitting it
    /// would hide a case from the compiler's exhaustiveness check, which is the whole guard.
    /// Hence the exemption around it.
    public init(stored: String) {
        let parts = stored.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let argument = parts.count == 2 ? String(parts[1]) : nil
        switch parts[0] {
        case "unsupportedFormat": self = argument.map { .unsupportedFormat($0) } ?? .unknown
        case "unreadable": self = .unreadable
        case "unauthorized": self = .unauthorized
        case "empty": self = .empty
        case "refusedAddress": self = .refusedAddress
        case "redirect": self = .redirect
        case "notAWebPage": self = .notAWebPage
        case "notAFeed": self = .notAFeed(argument)
        case "malformed": self = .malformed
        case "http": self = Int(argument ?? "").map { .http($0) } ?? .unknown
        case "noHost": self = .noHost
        case "timedOut": self = .timedOut
        case "offline": self = .offline
        case "unreachable": self = .unreachable
        default: self = .unknown
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
