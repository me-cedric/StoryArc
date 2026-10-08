internal import PhotosUI
internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The hero, and what the reader can do about the picture in it.
///
/// Tasks 2.2, 2.3 and 2.4 of `cover-for-every-publication`. ``DetailHero`` draws the artwork
/// and knows nothing about where it came from; this owns the choosing, so the hero stays a
/// view that takes a `CGImage` and the chooser can be read in one place.
///
/// **`PhotosPicker` and nothing else.** It is `PHPickerViewController`, which runs out of
/// process and hands this app the one picture the reader selected — so there is no
/// photo-library permission to ask for, and `design.md`'s rule about not asking for what you
/// do not need is kept by the platform rather than by us. A document picker or a library
/// authorisation would both put a prompt in front of a reader who only wants to set a
/// picture, and `design.md` records that decision at length.
struct DetailCoverChoice: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let cover: CGImage?

    @Environment(\.openURL) private var openURL

    @State private var isFinding = false
    /// The address the system browser is showing, while it is.
    @State private var browsing: URL?
    @State private var isChoosing = false
    @State private var picked: PhotosPickerItem?
    @State private var hasChosenCover = false
    @State private var isUnreadable = false
    /// The menu row that waits for a yes, while one does.
    @State private var asking: CoverMenuRow?

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            DetailHero(publication: publication, cover: cover, menu: menu)
            controls
        }
        .photosPicker(isPresented: $isChoosing, selection: $picked, matching: .images)
        .coverRemoval(asking: $asking) {
            Task {
                await model.removeChosenCover(for: publication)
                hasChosenCover = false
            }
        }
        .sheet(isPresented: $isFinding) {
            CoverFinderSheet(publication: publication, model: model) { stored in
                isUnreadable = !stored
                hasChosenCover = hasChosenCover || stored
            }
        }
        #if os(iOS)
        .sheet(isPresented: Binding(get: { browsing != nil }, set: { if !$0 { browsing = nil } })) {
            if let browsing { SystemBrowser(url: browsing).ignoresSafeArea() }
        }
        #endif
        .task(id: publication.id) { hasChosenCover = model.hasChosenCover(for: publication) }
        .onChange(of: picked) { _, item in Task { await adopt(item) } }
    }

    private var handoff: CoverSearchHandoff {
        CoverSearchHandoff(
            title: publication.displayTitle, author: publication.authors.first, open: openInBrowser
        )
    }

    /// The cover's menu, as far as the lookup switch allows.
    ///
    /// Task 6.2. The title search is here only while the switch is on; the web hand-off is
    /// always here, because the browser makes that request and the app does not.
    private var menu: CoverMenu {
        let offer = model.coverFinderOffer()
        return CoverMenu(
            hasCover: cover != nil,
            rows: CoverMenu.rows(
                find: offer.findACover, web: offer.webSearch, send: false, remove: hasChosenCover
            ),
            webSearchEnabled: handoff.destination != nil,
            act: select
        )
    }

    private func select(_ row: CoverMenuRow) {
        if row.asksFirst {
            asking = row
            return
        }
        switch row {
        case .choose: isChoosing = true
        case .find: isFinding = true
        case .searchWeb:
            let handoff = handoff
            if let url = handoff.destination { handoff.open(url) }
        case .remove, .sendToServer: break
        }
    }

    /// What the hero itself cannot carry.
    ///
    /// An empty well is already the way in, but a well that is silently tappable is a well
    /// nobody taps, so the same menu is offered in words underneath. A publication that has a
    /// cover has its edit button on the cover, and nothing here but the two sentences that
    /// are true of it. The warning is drawn only where it is true.
    @ViewBuilder
    private var controls: some View {
        VStack(spacing: StoryArcSpace.xs) {
            if cover == nil {
                CoverAddMenu(menu: menu)
            }

            // `cover-art`'s *A publication with no digest*: an image folder and a server row
            // have no content digest, so the choice is filed under the path and a move loses
            // it. Said here rather than nowhere, because a silent loss is worse than a
            // stated limit — and said only once the reader has something to lose.
            if hasChosenCover, model.chosenCoverIsTiedToPath(for: publication) {
                Text("cover.tiedToPath", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if isUnreadable {
                Text("cover.unreadable", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(StoryArcColor.Status.offline)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Hands the address to the system browser and keeps nothing it shows.
    private func openInBrowser(_ url: URL) {
        #if os(iOS)
        browsing = url
        #else
        openURL(url)
        #endif
    }

    /// Takes the picture the reader chose and makes it this publication's cover.
    ///
    /// The picker hands over bytes rather than a file, which is the whole of what this app
    /// ever learns about the reader's photo library: no album, no asset identifier, no second
    /// picture. Nothing is fetched and nothing is sent.
    private func adopt(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        picked = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              await model.setCover(data, for: publication)
        else {
            isUnreadable = true
            return
        }
        isUnreadable = false
        hasChosenCover = true
    }
}
