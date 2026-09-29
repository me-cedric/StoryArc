import Catalogue
import LibraryFeature
import StoryArcCore
import SwiftUI

extension Scene {
    /// Lets a download that is under way keep going after the app leaves the screen.
    ///
    /// `offline-downloads`: a backgrounded download "continues under the platform's
    /// background transfer mechanism as far as the platform allows". The transfer itself
    /// belongs to the system; this is the other half of the bargain. The system wakes the
    /// app when a transfer lands and expects to be told when the app has finished reacting.
    /// Without that, iOS counts the wake-up against the app and grants fewer of them.
    ///
    /// **The app-wide pin set, not the default empty one — dl-core 1.13.**
    /// `BackgroundTransfers.shared(pins:)` keeps whichever pins its first caller gave it for
    /// the life of the process, and this background-event handler can be that first caller:
    /// the system may relaunch the app straight into this closure, with no catalogue page —
    /// and no other call to `DownloadQueue.shared()` — having run yet. `CertificatePins.app`
    /// is the one set `StoryArcApp.init` and every screen use too, so the session trusts every
    /// host a reader has pinned, whichever caller builds it first, and a pin accepted later in
    /// this process as well.
    func continuingDownloadsInBackground() -> some Scene {
        backgroundTask(.urlSession(BackgroundTransfers.identifier)) {
            await withCheckedContinuation { continuation in
                BackgroundTransfers.shared(pins: .app).onFinishedEvents { continuation.resume() }
            }
        }
    }
}

extension View {
    /// Runs everything below in the language the reader chose.
    ///
    /// `localization` requires the override to switch "immediately without a restart", and
    /// `Bundle.main`'s language is fixed at launch, so nothing is reloaded: SwiftUI resolves
    /// a `Text` against the environment's locale, and changing that redraws the interface in
    /// the new language on the next frame. ``InterfaceLanguage`` carries the same choice to
    /// the strings built outside a view.
    func speaking(_ tag: String?) -> some View {
        InterfaceLanguage.choose(tag)
        return environment(\.locale, .storyArc)
    }
}
