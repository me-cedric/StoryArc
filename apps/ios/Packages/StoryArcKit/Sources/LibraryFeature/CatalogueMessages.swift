internal import Foundation
internal import Catalogue

/// What a reader is told when a catalogue does not answer the way it should.
///
/// One place, because the same failure can arrive while adding a catalogue and while
/// browsing it, and two sets of words for one condition is how a bug report ends up
/// describing something nobody can find.
///
/// `opds-catalog` requires the app to say "what it received — an HTML page, a redirect, a
/// 404 — instead of reporting a generic failure", so each case has its own sentence.
enum CatalogueMessages {
    static func describe(_ error: OpdsError) -> String {
        switch error {
        case .unauthorized:
            String(localized: "catalogue.error.unauthorized", bundle: .module, locale: .storyArc)
        case .empty:
            String(localized: "catalogue.error.empty", bundle: .module, locale: .storyArc)
        case .notAFeed(.html):
            String(localized: "catalogue.error.html", bundle: .module, locale: .storyArc)
        case let .notAFeed(.unrecognised(contentType)):
            String(
                format: String(localized: "catalogue.error.notAFeed", bundle: .module, locale: .storyArc),
                contentType ?? String(localized: "catalogue.error.unknownType", bundle: .module, locale: .storyArc)
            )
        case let .malformed(reason):
            String(
                format: String(localized: "catalogue.error.malformed", bundle: .module, locale: .storyArc),
                reason
            )
        case let .http(status):
            String(
                format: String(localized: "catalogue.error.http", bundle: .module, locale: .storyArc),
                status,
                HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }
    }

    /// A transport failure, said in terms of what the reader can do about it.
    static func reachability(_ error: any Error) -> String {
        switch (error as? URLError)?.code {
        case .some(.cannotFindHost), .some(.cannotConnectToHost):
            String(localized: "catalogue.error.noHost", bundle: .module, locale: .storyArc)
        case .some(.timedOut):
            String(localized: "catalogue.error.timedOut", bundle: .module, locale: .storyArc)
        case .some(.notConnectedToInternet):
            String(localized: "catalogue.error.offline", bundle: .module, locale: .storyArc)
        default:
            error.localizedDescription
        }
    }
}
