import CoreGraphics
@testable import LibraryFeature
import Playback
import PlayerFeature
import StoryArcCore
import SwiftUI
import XCTest

/// A narrated book that makes no sound: three chapters of known length, mid-way through the
/// second. The centre needs a source to start, and the surfaces never learn which kind it is.
private final class StillNarration: PlaybackSource {
    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    let parts = [
        PlaybackPart(index: 0, title: "The Map Room", duration: 1_820),
        PlaybackPart(index: 1, title: "A Coast Not Yet Drawn", duration: 2_410),
        PlaybackPart(index: 2, title: "Ink and Salt", duration: 1_960),
    ]
    let place = PlaybackPlace(partIndex: 1, offset: 754)
    let skipUnit: SkipUnit = .time
    let unreadablePartCount = 0

    func play() {}
    func pause() {}
    func stop() {}
    func setSpeed(_ speed: PlaybackSpeed) {}
    func seek(toPart index: Int, offset: TimeInterval) {}
    func skip(_ direction: SkipDirection, by interval: TimeInterval) {}
}

@MainActor
final class DetailAndPlayerCatalogueTests: XCTestCase {
    private struct Playing {
        let centre: PlayerCentre
        let cover: CGImage
    }

    private func playing() -> Playing {
        let entry = CatalogueLibrary.entries[5]
        let publication = CatalogueLibrary.publication(entry, index: 5)
        let centre = PlayerCentre()
        centre.begin(
            SpokenBook(publication: publication, url: URL(fileURLWithPath: "/fixtures/5.m4b")),
            source: StillNarration()
        )
        return Playing(centre: centre, cover: CatalogueCover.image(for: entry.title, hue: entry.hue))
    }

    func testCatalogue05PublicationWithCover() {
        let model = CatalogueLibrary.model()
        let publication = model.publications[0]
        assertCatalogue("05-publication-with-cover", delay: 2) {
            NavigationStack {
                PublicationDetailView(publication: publication, model: model, onOpen: { _, _ in })
            }
        }
    }

    func testCatalogue06PublicationWithoutCover() {
        let model = CatalogueLibrary.model(withCovers: false)
        let publication = model.publications[0]
        assertCatalogue("06-publication-without-cover", delay: 2) {
            NavigationStack {
                PublicationDetailView(publication: publication, model: model, onOpen: { _, _ in })
            }
        }
    }

    /// The page of a publication whose file is not on this device. The ellipsis menu is then the
    /// only action, and it once stretched to the height left in the window.
    func testCatalogue05bPublicationUnavailable() {
        let model = CatalogueLibrary.model()
        let publication = model.publications[0]
        model.locations.removeAll()
        assertCatalogue("05b-publication-unavailable", delay: 2) {
            NavigationStack {
                PublicationDetailView(publication: publication, model: model, onOpen: { _, _ in })
            }
        }
    }

    func testCatalogue07FullPlayer() {
        let playing = playing()
        assertCatalogue("07-full-player", delay: 1.5) {
            FullPlayerView(centre: playing.centre, coverLookup: { _, _ in playing.cover })
        }
    }

    /// The dock is the content of the tab bar's bottom accessory, which supplies its glass
    /// capsule, so it is drawn there and not on a bare screen.
    func testCatalogue08CompactPlayerBar() {
        let centre = playing().centre
        let model = CatalogueLibrary.model()
        assertCatalogue("08-compact-player-bar", delay: 3) {
            TabView {
                Tab("Home", systemImage: "house") { HomeScreen(model: model) }
                Tab("Library", systemImage: "books.vertical") { LibraryView(model: model) }
                Tab("Search", systemImage: "magnifyingglass") { LibraryView(model: model, surface: .search) }
            }
            .tabViewBottomAccessory {
                PlayerDock(centre: centre, isShowingPlayer: .constant(false), onReturn: { _, _ in })
            }
        }
    }
}
