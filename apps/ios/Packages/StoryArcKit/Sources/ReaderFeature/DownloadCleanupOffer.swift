/// What the end screen offers about this publication's download.
///
/// Decision D7. `nil` for most publications: `offline-downloads` sweeps a *download*,
/// and a publication opened from a folder or read from a share was never one.
public struct DownloadCleanupOffer {
    /// Whether the automatic sweep is on for this device. On: the end screen states
    /// that the download goes when the reader closes, with `onKeep` to stop that.
    /// Off: the end screen offers `onRemove` instead — the sweep will not do it.
    public let automaticCleanupIsOn: Bool
    public let onRemove: () -> Void
    public let onKeep: () -> Void

    public init(
        automaticCleanupIsOn: Bool,
        onRemove: @escaping () -> Void,
        onKeep: @escaping () -> Void
    ) {
        self.automaticCleanupIsOn = automaticCleanupIsOn
        self.onRemove = onRemove
        self.onKeep = onKeep
    }
}

/// What the end screen shows about the download, from whether there is one to offer
/// anything about at all. Android's `DownloadCleanupPresentation` is the same table.
public enum DownloadCleanupPresentation: Equatable {
    /// No offer at all — most publications were never a download.
    case none
    /// The sweep is off: an action to remove the download now.
    case offerRemoval
    /// The sweep is on: a sentence saying so, and an action to keep this one anyway.
    case stateAndOfferKeep

    /// Lifted out of the view, so `DownloadCleanupPresentationTests` can drive it with
    /// a plain optional rather than a screen.
    public static func resolved(for offer: DownloadCleanupOffer?) -> DownloadCleanupPresentation {
        guard let offer else { return .none }
        return offer.automaticCleanupIsOn ? .stateAndOfferKeep : .offerRemoval
    }
}
