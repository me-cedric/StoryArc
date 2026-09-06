internal import SwiftUI

internal import Formats

/// The words for a refusal, in the reader's language.
///
/// **The seam this file is.** `Formats` discovers the refusal and names it as a case;
/// `LibraryFeature` says what that case means, because this is the module with a catalogue.
/// `localization`'s *A refusal speaks the reader's language*: "it is the text most likely to
/// be written far from any screen — in the layer that discovered the problem", and naming it
/// in English only does not satisfy the requirement.
///
/// **`Formats` gains no catalogue, deliberately.** `pnpm strings:ios` reads one table per
/// module, and that module draws nothing — a second table there would be a table for a module
/// with no views, holding the sentences this file holds instead.
///
/// Every key is a literal here, one per case. `scripts/ios-strings.mjs` reads `Text("…")` out
/// of the source, so a key reached through a variable is a key that gate cannot see, which is
/// how thirty sentences shipped. `SkipReasonWordsTests` asserts that, case for case.
///
/// Android's `skipReasonText` maps the same cases to the same names in `strings.xml`.
extension SkipReason {
    /// What the library says about this refusal.
    ///
    /// The format's name in the first case is content, not a sentence: `localization`'s
    /// *A sentence built around content* shows it as it is and translates the words around it.
    var sentence: Text {
        switch self {
        case let .unsupportedFormat(format):
            Text("library.skipped.reason.unsupported \(format)", bundle: .module)
        case .notThere:
            Text("library.skipped.reason.notThere", bundle: .module)
        case .formatNotRecognised:
            Text("library.skipped.reason.formatNotRecognised", bundle: .module)
        case .archivePasswordProtected:
            Text("library.skipped.reason.archivePasswordProtected", bundle: .module)
        case .archiveUnreadable:
            Text("library.skipped.reason.archiveUnreadable", bundle: .module)
        case .pdfUnopenable:
            Text("library.skipped.reason.pdfUnopenable", bundle: .module)
        // Android's wording, not this platform's. It names the kind of thing, and
        // `localization`'s *One sentence, assembled differently* makes the more informative
        // one the agreed wording. Content protection only ever applies to audio here, so
        // naming it costs nothing and reads better in a list where each row carries a name.
        case .contentProtected:
            Text("library.skipped.reason.contentProtected", bundle: .module)
        // *A failure with no sentence written for it*: a translated general refusal, rather
        // than text produced for a maintainer. There is no maintainer's copy anywhere.
        // `LibraryScanner.swift:358` catches the throw and keeps this case alone, and the
        // diagnostic export carries nothing about a scan, so the description of the failure
        // is discarded. The discard is older than this file. Giving it a route needs its own
        // change, on both platforms.
        case .unknown:
            Text("library.skipped.reason.unknown", bundle: .module)
        }
    }
}
