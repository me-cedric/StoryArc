/// What the end screen offers about this publication's download.
///
/// Decision D7. `nil` for most publications: `offline-downloads` sweeps a *download*,
/// and a publication opened from a folder or read from a share was never one. Both
/// actions take effect when the reader closes, so the undo shows where the reader is.
public struct DownloadCleanupOffer {
    /// Whether this download goes when the reader closes: the automatic sweep is on and
    /// the reader has not kept it, or the reader asked for it here. A function, read when
    /// the end screen shows, so a choice made on an earlier visit to it is not lost.
    public let isRemovedOnClose: () -> Bool
    /// "Remove download": the download goes when the reader closes, with the sweep's own
    /// undo in the library.
    public let onRemove: () -> Void
    /// "Keep": the sweep skips this download from now on.
    public let onKeep: () -> Void

    public init(
        isRemovedOnClose: @escaping () -> Bool,
        onRemove: @escaping () -> Void,
        onKeep: @escaping () -> Void
    ) {
        self.isRemovedOnClose = isRemovedOnClose
        self.onRemove = onRemove
        self.onKeep = onKeep
    }
}

/// What the end screen shows about the download, from whether there is one to offer
/// anything about at all. Android's `DownloadCleanupPresentation` is the same table.
public enum DownloadCleanupPresentation: Equatable {
    /// No offer at all — most publications were never a download.
    case none
    /// The download stays: an action to have it removed when the reader closes.
    case offerRemoval
    /// The download goes when the reader closes: a sentence saying so, and an action to
    /// keep this one anyway.
    case stateAndOfferKeep

    /// Lifted out of the view, so `DownloadCleanupPresentationTests` can drive it with
    /// a plain optional rather than a screen. `choice` is the reader's tap on this
    /// screen — true for "Remove download", false for "Keep" — which answers at once,
    /// without waiting for anything to read the store again.
    public static func resolved(
        for offer: DownloadCleanupOffer?, choice: Bool? = nil
    ) -> DownloadCleanupPresentation {
        guard let offer else { return .none }
        return (choice ?? offer.isRemovedOnClose()) ? .stateAndOfferKeep : .offerRemoval
    }
}
