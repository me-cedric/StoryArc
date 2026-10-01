import SwiftUI

import StoryArcCore

/// The two small glossaries `DownloadQueueRow` reads from: why a download is not moving,
/// and what its last attempt did.
///
/// Split out of `DownloadQueueSection.swift`, which reached the 400-line cap this project
/// enforces — the seam was already there, since both extensions are pure mappings the row
/// reads and neither composes a view of its own.
extension Download.Pause {
    /// Why this one is not moving, in the reader's terms.
    ///
    /// The app target's own copy of the mapping `SettingsFeature` carries, because the
    /// strings are in this bundle now: the queue moved out of Settings, and a key looked up
    /// in the wrong bundle renders as the key.
    var explanationKey: LocalizedStringKey {
        switch self {
        case .byReader: "downloads.paused.byReader"
        case .waitingForWiFi: "downloads.paused.waitingForWiFi"
        case .outOfSpace: "downloads.paused.outOfSpace"
        }
    }
}

extension Download.LastAttempt {
    /// What this attempt did, in the reader's terms.
    var rowKey: LocalizedStringKey {
        switch self {
        case .resumed: "downloads.attempt.resumed"
        case .restarted: "downloads.attempt.restarted"
        }
    }
}
