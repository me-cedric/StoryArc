// CarPlay is in every iOS SDK, so this file compiles wherever the app does. Activating the
// scene is what needs `com.apple.developer.carplay-audio`, and ADR-0011 records that this
// project has no Apple development team to request it against. The guard is here so the
// reason is stated where the code is, and so a host build of the same sources is not
// surprised by a framework iOS has and macOS does not.
#if canImport(CarPlay)
import CarPlay
import UIKit

import Playback
import StoryArcCore

/// What a car asks the app for.
///
/// One provider and two actions, in the shape ``PlayerCentre`` already uses for the facts
/// only the app layer holds — `onArtwork`, `onRecord`, `onRecallSpeed`. A car scene is not
/// SwiftUI's scene, so it can read no environment; a seam the app installs once is how the
/// other three cross the same boundary. `StoryArcApp.init` installs all three, task 16.4.
///
/// **Reachable in the simulator, not yet in a car.** The simulator build carries
/// `com.apple.developer.carplay-audio` and the scene manifest, so the CarPlay Simulator opens
/// the scene. A device build carries neither, because the entitlement needs an Apple
/// development team this project does not have, ADR-0011. The last step is the owner's, in
/// `design.md`'s "The day an Apple team exists".
///
/// **A cold start from a car is covered.** The seams are installed, and `restoreFolders()` is
/// called, in `StoryArcApp.init`. A car that launches the app with no phone scene never builds
/// the `WindowGroup`, so a `.task` there would leave the list empty.
@MainActor
enum CarScene {

    /// The audiobooks on this device, in the order the library holds them.
    static var onDevice: (@MainActor () -> [SpokenBook])?

    /// Start, or return to, one of those books.
    static var onListen: (@MainActor (SpokenBook) -> Void)?

    /// The last audiobook a listener was in the middle of, read from `ProgressStore` —
    /// Task 16.4's "read the last listened audiobook … for the first row". `PlayerCentre`
    /// only knows one once a session has started this launch; a car that connects before
    /// anything has played has no other way to offer the book a listener left off at.
    static var lastListened: (@MainActor () async -> SpokenBook?)?
}

/// The car's two screens, and nothing else.
///
/// `audio-playback`'s "Listening in a car" asks for a flat list and the car's own transport
/// controls. The list is ``CPListTemplate``; the transport is ``CPNowPlayingTemplate``,
/// whose buttons are the remote commands `NowPlaying` already wires — so a car's play,
/// pause and skip drive the same session as the lock screen rather than a second one.
///
/// Which rows the list holds is ``CarShelf``'s, in `StoryArcKit`, where a test can read
/// them. This file is only the platform's vocabulary for that list, which is the division
/// `HomeScreenActions` draws for the home-screen menu.
@MainActor
final class CarSceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interface: CPInterfaceController?

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        interface = interfaceController
        let root = list(continuing: PlayerCentre.shared.book)
        interfaceController.setRootTemplate(root, animated: false, completion: nil)

        // A car that connects before this launch has played anything has no live session
        // to offer — `PlayerCentre.shared.book` is nil until `listen(to:at:)` runs once —
        // so the book a listener left off at comes from `ProgressStore` instead, read
        // asynchronously and set as the root once it answers. Skipped once a session has
        // started: that book is the one a listener reaches for, and it would be wrong to
        // replace it with an older one `ProgressStore` has not caught up to yet.
        guard PlayerCentre.shared.book == nil else { return }
        Task { [weak self] in
            guard let self, let resumed = await CarScene.lastListened?() else { return }
            self.interface?.setRootTemplate(self.list(continuing: resumed), animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        interface = nil
    }

    private func list(continuing playing: SpokenBook?) -> CPListTemplate {
        let rows = CarShelf.rows(continuing: playing, onDevice: CarScene.onDevice?() ?? [])
        return CPListTemplate(
            title: String(localized: "car.audiobooks", bundle: .main, locale: .storyArc),
            sections: [CPListSection(items: rows.map(item(for:)))]
        )
    }

    /// One row, and what pressing it does.
    ///
    /// The now-playing screen is pushed rather than set as the root: a listener who chose a
    /// book is looking at the player, and the list they chose from is one press back. The
    /// handler's completion is called last because the car keeps the row spinning until it
    /// arrives.
    private func item(for book: SpokenBook) -> CPListItem {
        let row = CPListItem(text: book.label.title, detailText: book.label.detail)
        row.handler = { [weak self] _, completion in
            CarScene.onListen?(book)
            self?.interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
        }
        return row
    }
}
#endif
