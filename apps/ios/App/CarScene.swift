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
/// One provider and one action, in the shape ``PlayerCentre`` already uses for the facts
/// only the app layer holds — `onArtwork`, `onRecord`, `onRecallSpeed`. A car scene is not
/// SwiftUI's scene, so it can read no environment; a seam the app installs once is how the
/// other three cross the same boundary.
///
/// **Nothing installs these yet, and that is deliberate.** The rows are only observable in
/// a car, the scene cannot activate without the entitlement, and §12.6 of the task list
/// carries the block. `design.md`'s "The day an Apple team exists" names this as one of the
/// four steps the owner takes.
@MainActor
enum CarScene {

    /// The audiobooks on this device, in the order the library holds them.
    static var onDevice: (@MainActor () -> [SpokenBook])?

    /// Start, or return to, one of those books.
    static var onListen: (@MainActor (SpokenBook) -> Void)?
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
        interfaceController.setRootTemplate(list(), animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        interface = nil
    }

    private func list() -> CPListTemplate {
        let rows = CarShelf.rows(
            // The live session, because that is what the app knows without a second store.
            // A book in progress that outlives the app being killed is the same shared
            // snapshot ADR-0011 defers, and it is blocked on the same missing team.
            continuing: PlayerCentre.shared.book,
            onDevice: CarScene.onDevice?() ?? []
        )
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
