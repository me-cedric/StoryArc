public import Foundation

/// What a chosen cover was set on, from the point of view of writing it back to a source.
///
/// Every row a reader can set a cover on is one of these, so ``CoverWriteBack/offer(for:)``
/// is total and a new row has to choose a case rather than fall through to an offer.
public enum CoverWriteSubject: Sendable, Equatable, Hashable {
    /// A reading list on a Kavita server.
    ///
    /// `promoted` is the only ownership signal a client gets. Kavita answers
    /// `ReadingList/lists` with the lists the signed-in reader owns plus the promoted ones,
    /// so a list that is **not** promoted in that answer is necessarily theirs. A promoted
    /// list may belong to anybody, which is why it is not offered.
    case kavitaReadingList(id: Int, promoted: Bool)

    case kavitaSeries
    case kavitaChapter
    case kavitaCollection
    case kavitaLibrary

    /// Any row from an OPDS catalogue, of either version.
    case opds

    /// A file or folder on this device, which has no server to write to.
    case localFile
}

/// Whether the app offers to write a cover back, and to what.
public enum CoverWriteOffer: Sendable, Equatable, Hashable {
    /// Nothing is offered. The cover stays on this device.
    case none

    /// Kavita's reading-list cover route, for the list with this identifier.
    case kavitaReadingList(id: Int)
}

/// The one place that decides whether a write-back is offered.
///
/// `cover-art` requires the app to offer a write "only where that source accepts one from
/// the reader who is signed in, and SHALL NOT offer it anywhere else". Kavita has six
/// cover-upload routes and five of them need the administrator role, so an offer on a
/// series, a chapter, a collection or a library is a button that answers 403 to most
/// readers — which teaches them the app is broken. OPDS has no write operation in version
/// 1.2 or 2.0, so there is nothing there to offer either.
///
/// One function rather than a condition at each call site, because the drift this guards
/// against is a later screen growing its own copy of the condition and getting it wrong.
public enum CoverWriteBack {
    public static func offer(for subject: CoverWriteSubject) -> CoverWriteOffer {
        switch subject {
        case let .kavitaReadingList(id, promoted):
            promoted ? .none : .kavitaReadingList(id: id)
        case .kavitaSeries, .kavitaChapter, .kavitaCollection, .kavitaLibrary, .opds, .localFile:
            .none
        }
    }
}
