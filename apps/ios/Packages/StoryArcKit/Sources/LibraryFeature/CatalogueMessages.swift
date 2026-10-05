internal import Foundation
import OSLog
internal import Catalogue
internal import StoryArcCore

private let catalogueMessagesLog = Logger(subsystem: "app.storyarc.catalogue", category: "messages")

enum CatalogueMessages {
    /// What a catalogue error *is*, as a reason the record can keep.
    ///
    /// `localization` 15.9 split this in two: deciding which failure happened, which is here,
    /// and saying it in words, which is ``DownloadFailureWords``. A download's record holds the
    /// first and the row draws the second, so a reader who changes language afterwards gets
    /// their own words rather than the ones the app spoke on the day it failed.
    static func reason(_ error: OpdsError) -> DownloadFailure {
        switch error {
        case .unauthorized: .unauthorized
        case .empty: .empty
        case .refusedAddress: .refusedAddress
        case .redirect: .redirect
        case .notAFeed(.html): .notAWebPage
        case let .notAFeed(.unrecognised(contentType)): .notAFeed(contentType)
        case let .malformed(reason):
            // The parser's own words, which are English and are a developer's. Logged rather
            // than shown, which is why the reader's reason carries no argument.
            logged(malformed: reason)
        case let .http(status): .http(status)
        }
    }

    /// Why a transfer could not reach the server at all, as a reason the record can keep.
    static func reaching(_ error: any Error) -> DownloadFailure {
        switch (error as? URLError)?.code {
        case .some(.cannotFindHost), .some(.cannotConnectToHost): .noHost
        case .some(.timedOut): .timedOut
        case .some(.notConnectedToInternet): .offline
        default: logged(unreachable: error)
        }
    }

    static func describe(_ error: OpdsError) -> String {
        DownloadFailureWords.sentence(reason(error))
    }

    static func reachability(_ error: any Error) -> String {
        DownloadFailureWords.sentence(reaching(error))
    }

    private static func logged(malformed reason: String) -> DownloadFailure {
        catalogueMessagesLog.error("malformed feed: \(reason, privacy: .public)")
        return .malformed
    }

    private static func logged(unreachable error: any Error) -> DownloadFailure {
        catalogueMessagesLog.error("catalogue unreachable: \(error, privacy: .public)")
        return .unreachable
    }
}
