internal import Foundation

public import StoryArcCore

/// A failed download's reason, said in the language the reader has chosen *now*.
///
/// `localization` 15.9: the sentence used to be composed when the download failed and written
/// into the record, so it kept the language the app spoke that day. Switching the app to
/// French left every failed row in English for ever. The record holds a
/// ``StoryArcCore/DownloadFailure`` now, and this is where it becomes words — at the moment a
/// row is drawn, which is the only moment the chosen language is known.
///
/// Here rather than in `StoryArcCore` because this is where the strings are, and `.storyArc`
/// is the locale the reader picked rather than the device's. Every key is written out in full
/// at its own case, as ``CatalogueMessages`` writes them: a key reached through a variable is
/// a key `pnpm strings:ios` cannot see.
///
/// Android's `DownloadFailureWords` is its twin.
public enum DownloadFailureWords {
    /// The sentence for whatever the record stored.
    ///
    /// Takes the stored spelling rather than the value, because every caller has a record and
    /// ``StoryArcCore/DownloadFailure/init(stored:)`` is what turns an older build's sentence
    /// into ``StoryArcCore/DownloadFailure/unknown``.
    public static func sentence(stored: String) -> String {
        sentence(DownloadFailure(stored: stored))
    }

    // One branch per case, and the compiler checks that none is missing — which is the point
    // of the closed set. Splitting it would take that check away in exchange for the count.
    // swiftlint:disable:next cyclomatic_complexity
    public static func sentence(_ failure: DownloadFailure) -> String {
        switch failure {
        case let .unsupportedFormat(format):
            String(
                format: String(localized: "catalogue.acquire.unsupported",
                               bundle: .module.inChosenLanguage, locale: .storyArc),
                format
            )
        case .unreadable:
            String(localized: "catalogue.acquire.unreadable", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .unauthorized:
            String(localized: "catalogue.error.unauthorized", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .empty:
            String(localized: "catalogue.error.empty", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .refusedAddress:
            String(localized: "catalogue.error.refusedAddress", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .redirect:
            String(localized: "catalogue.error.redirect", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .notAWebPage:
            String(localized: "catalogue.error.html", bundle: .module.inChosenLanguage, locale: .storyArc)
        case let .notAFeed(contentType):
            String(
                format: String(localized: "catalogue.error.notAFeed",
                               bundle: .module.inChosenLanguage, locale: .storyArc),
                contentType
                    ?? String(localized: "catalogue.error.unknownType",
                              bundle: .module.inChosenLanguage, locale: .storyArc)
            )
        case .malformed:
            String(localized: "catalogue.error.malformed", bundle: .module.inChosenLanguage, locale: .storyArc)
        case let .http(status):
            String(
                format: String(localized: "catalogue.error.http", bundle: .module.inChosenLanguage, locale: .storyArc),
                status
            )
        case .noHost:
            String(localized: "catalogue.error.noHost", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .timedOut:
            String(localized: "catalogue.error.timedOut", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .offline:
            String(localized: "catalogue.error.offline", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .unreachable:
            String(localized: "catalogue.error.unreachable", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .unknown:
            String(localized: "downloads.failure.unknown", bundle: .module.inChosenLanguage, locale: .storyArc)
        }
    }
}
