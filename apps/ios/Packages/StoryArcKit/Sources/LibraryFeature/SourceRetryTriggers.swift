internal import SwiftUI

internal import Catalogue
internal import Persistence
internal import StoryArcCore

/// The two occasions a source is asked again that the backoff does not cover.
///
/// Its own file because `LibraryView.swift` sits against SwiftLint's 400-line cap, and the cap
/// was pointing at a seam: the view draws a shelf, and *keeping the sources answering* is a rule
/// with its own lifetime. `LibrarySourceHealth` already owns the deciding, `SourceReachability`
/// owns the conditions, and this owns only the wiring.
struct SourceRetryTriggers: ViewModifier {
    let model: LibraryModel
    let isReading: @MainActor () -> Bool

    /// The view's own, not a fresh pair.
    ///
    /// **The first version of this file built its own and that was a defect.** `LibraryView`
    /// loads the reader's pinned certificates from the store into `@State`; a `CertificatePins()`
    /// constructed here would be empty, so a probe fired by a regained network would trust
    /// nothing the reader had pinned and fail against exactly the servers pinning exists for.
    /// The credentials are the same argument in a quieter register.
    let credentials: CredentialStore
    let pins: CertificatePins

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // The two occasions the backoff does not cover, per `sources`' *Retry policy*.
            //
            // **A separate `.task` because it has a different lifetime and a different
            // source.** The backoff above stops as soon as nothing is away; these two go on
            // mattering for as long as the library is on screen, and they arrive from the
            // system rather than from the state of the registry. Merging them would mean
            // the trigger stream dying the moment every source answered.
            //
            // Both go through ``SourceReachability``, which is where the reading guard and
            // the "something is away" condition live, so a third occasion has to be answered
            // there rather than inheriting whatever these two happen to do.
            .task {
                for await trigger in SourceReachability.triggers(from: NetworkPaths.satisfied()) {
                    await model.probe(
                        on: trigger,
                        credentials: credentials,
                        pins: pins,
                        isReading: isReading()
                    )
                }
            }
            // Returning to the foreground is the other occasion, and it is **not** the
            // `.task` above restarting: a `.task` fires on appear, and backgrounding does
            // not disappear a view. This view's own header says so a hundred lines up, and
            // `retryUnreachableSources` claimed the opposite until 2026-09-03.
            .onChange(of: scenePhase) { was, now in
                guard was != .active, now == .active else { return }
                Task {
                    await model.probe(
                        on: .returnedToForeground,
                        credentials: credentials,
                        pins: pins,
                        isReading: isReading()
                    )
                }
            }
    }
}
